import Foundation
import CoreLocation
import MapKit
import PickerCore

/// "I'm on my way" (1.1): shares an arrival time with the group, never a
/// location. One tap works out the drive time once (Apple Maps, like
/// leave-by) and writes sessions/{id}/eta/{uid}; the server tells everyone.
/// In the app, it then keeps the time fresh while you drive and notices when
/// you arrive (ForkRoad/Services/OnMyWayLive.swift, through `liveTracker`).
/// Shared by the app and the iMessage app (one-shot there).
@MainActor
enum OnMyWay {
    /// Within this distance of the place counts as arrived.
    static let arrivalMeters: CLLocationDistance = 100

    /// Live updates while driving. Set by the app at launch; nil in the
    /// iMessage app, which can't run in the background.
    static var liveTracker: (@MainActor (_ sessionID: String, _ destination: CLLocationCoordinate2D, _ meetTime: Date) -> Void)?
    static var stopTracker: (@MainActor (_ sessionID: String) -> Void)?
    /// You arrived (tracker, "I'm here", or tapping On my way at the door):
    /// the app takes the Lock Screen countdown down if set to "When I arrive".
    static var onArrived: (@MainActor (_ sessionID: String) -> Void)?

    /// What you last shared per plan, so a live refresh keeps "late" (saved,
    /// so it survives iOS ending the app mid-drive).
    struct Shared: Codable {
        var status: GroupETA.Status
        var lateMinutes: Int?
        var lateNote: String?
        var eta: Date?
    }

    private static let sharedKey = "onMyWay.shared"

    private(set) static var shared: [String: Shared] = {
        guard let data = UserDefaults.standard.data(forKey: sharedKey),
              let saved = try? JSONDecoder().decode([String: Shared].self, from: data) else { return [:] }
        return saved
    }() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(shared), forKey: sharedKey) }
    }

    /// The arrival time you last shared for a plan.
    static var lastSharedETA: [String: Date] { shared.compactMapValues(\.eta) }

    /// The card shows from a few hours before the meet time until a bit after.
    static func isRelevant(meetTime: Date, now: Date = Date()) -> Bool {
        let until = meetTime.timeIntervalSince(now)
        return until < 4 * 3600 && until > -45 * 60
    }

    /// One tap: your drive time from here, shared. Returns the arrival time
    /// (nil when location is off or there's no route; you're still "on the way").
    ///
    /// `askForLocation` false (the Lock Screen buttons, which run in the
    /// background where no prompt can show and no fix comes): skips location
    /// and uses `fallbackTravelMinutes` (your known drive time) instead.
    @discardableResult
    static func start(sessionID: String, destination: CLLocationCoordinate2D, meetTime: Date,
                      askForLocation: Bool = true, fallbackTravelMinutes: Int = 0) async throws -> Date? {
        var eta: Date?
        var allowed = false
        if askForLocation {
            allowed = await OneShotLocation.shared.requestPermission()
            if allowed, let here = await OneShotLocation.shared.current() {
                let distance = CLLocation(latitude: here.latitude, longitude: here.longitude)
                    .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
                if distance <= arrivalMeters {
                    try await arrived(sessionID: sessionID)
                    return Date()
                }
                eta = await arrival(from: here, to: destination)
            }
        }
        if eta == nil, fallbackTravelMinutes > 0 {
            eta = Date().addingTimeInterval(TimeInterval(fallbackTravelMinutes * 60))
        }
        try await GroupService.shared.shareETA(sessionID: sessionID, eta: eta, status: .onTheWay, leftAt: Date())
        shared[sessionID] = Shared(status: .onTheWay, eta: eta)
        UsageStats.record(.onMyWay)
        // Live updates need location; without it you're "on the way" with one time.
        if allowed { liveTracker?(sessionID, destination, meetTime) }
        return eta
    }

    /// A fresh time while driving (from the live tracker). Keeps "late".
    static func refresh(sessionID: String, eta: Date?) async {
        var current = shared[sessionID] ?? Shared(status: .onTheWay)
        guard current.status != .arrived else { return }
        do {
            try await GroupService.shared.shareETA(sessionID: sessionID, eta: eta, status: current.status,
                                                    lateMinutes: current.lateMinutes, lateNote: current.lateNote)
            current.eta = eta
            shared[sessionID] = current
        } catch {
            // Offline for a moment: the next refresh tries again.
        }
    }

    /// "Running late": +10 / +15 / +30 minutes past the meet time, or nil
    /// minutes for "I'll text you".
    static func runningLate(sessionID: String, minutes: Int?, meetTime: Date) async throws {
        let eta = minutes.map { meetTime.addingTimeInterval(TimeInterval($0 * 60)) }
        let note = minutes == nil ? "text" : nil
        try await GroupService.shared.shareETA(sessionID: sessionID, eta: eta, status: .late,
                                                lateMinutes: minutes, lateNote: note)
        shared[sessionID] = Shared(status: .late, lateMinutes: minutes, lateNote: note, eta: eta)
        UsageStats.record(.runningLate)
    }

    /// You're there (by tapping "I'm here", or the live tracker noticing).
    static func arrived(sessionID: String) async throws {
        // Share first: stopping the tracker cancels the task this may be running in.
        defer {
            stopTracker?(sessionID)
            onArrived?(sessionID)
        }
        try await GroupService.shared.shareETA(sessionID: sessionID, eta: Date(), status: .arrived)
        shared[sessionID] = Shared(status: .arrived, eta: Date())
    }

    /// "Stop sharing".
    static func stop(sessionID: String) async {
        shared[sessionID] = nil
        stopTracker?(sessionID)
        await GroupService.shared.removeETA(sessionID: sessionID)
    }

    /// The plan ended or changed (reopened, new place): forget it here (the
    /// server deletes the shared times).
    static func reset(sessionID: String) {
        stopTracker?(sessionID)
        if shared[sessionID] != nil { shared[sessionID] = nil }
    }

    /// When you'd get there driving from `from`, leaving now (with traffic).
    static func arrival(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> Date? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        request.departureDate = Date()
        return try? await MKDirections(request: request).calculateETA().expectedArrivalDate
    }
}
