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

    /// The last thing you shared per plan, so a live refresh keeps "late".
    private(set) static var shared: [String: (status: GroupETA.Status, lateMinutes: Int?, lateNote: String?)] = [:]

    /// The card shows from a few hours before the meet time until a bit after.
    static func isRelevant(meetTime: Date, now: Date = Date()) -> Bool {
        let until = meetTime.timeIntervalSince(now)
        return until < 4 * 3600 && until > -45 * 60
    }

    /// One tap: your drive time from here, shared. Returns the arrival time
    /// (nil when location is off or there's no route; you're still "on the way").
    @discardableResult
    static func start(sessionID: String, destination: CLLocationCoordinate2D, meetTime: Date) async throws -> Date? {
        var eta: Date?
        let allowed = await OneShotLocation.shared.requestPermission()
        if allowed, let here = await OneShotLocation.shared.current() {
            let distance = CLLocation(latitude: here.latitude, longitude: here.longitude)
                .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
            if distance <= arrivalMeters {
                try await arrived(sessionID: sessionID)
                return Date()
            }
            eta = await arrival(from: here, to: destination)
        }
        shared[sessionID] = (.onTheWay, nil, nil)
        try await GroupService.shared.shareETA(sessionID: sessionID, eta: eta, status: .onTheWay, leftAt: Date())
        // Live updates need location; without it you're "on the way" with no time.
        if allowed { liveTracker?(sessionID, destination, meetTime) }
        return eta
    }

    /// A fresh time while driving (from the live tracker). Keeps "late".
    static func refresh(sessionID: String, eta: Date?) async {
        let current = shared[sessionID] ?? (.onTheWay, nil, nil)
        try? await GroupService.shared.shareETA(sessionID: sessionID, eta: eta, status: current.status,
                                                lateMinutes: current.lateMinutes, lateNote: current.lateNote)
    }

    /// "Running late": +10 / +15 / +30 minutes past the meet time, or nil
    /// minutes for "I'll text you".
    static func runningLate(sessionID: String, minutes: Int?, meetTime: Date) async throws {
        let eta = minutes.map { meetTime.addingTimeInterval(TimeInterval($0 * 60)) }
        let note = minutes == nil ? "text" : nil
        shared[sessionID] = (.late, minutes, note)
        try await GroupService.shared.shareETA(sessionID: sessionID, eta: eta, status: .late,
                                                lateMinutes: minutes, lateNote: note)
    }

    /// You're there (by tapping "I'm here", or the live tracker noticing).
    static func arrived(sessionID: String) async throws {
        shared[sessionID] = (.arrived, nil, nil)
        // Share first: stopping the tracker cancels the task this may be running in.
        defer {
            stopTracker?(sessionID)
            onArrived?(sessionID)
        }
        try await GroupService.shared.shareETA(sessionID: sessionID, eta: Date(), status: .arrived)
    }

    /// "Stop sharing", or the plan ended or changed.
    static func stop(sessionID: String) async {
        shared[sessionID] = nil
        stopTracker?(sessionID)
        await GroupService.shared.removeETA(sessionID: sessionID)
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
