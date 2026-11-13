import Foundation
import CoreLocation
import PickerCore

/// "On my way", step 2 (1.1): after you tap it, keeps your arrival time
/// fresh every few minutes while you drive, and notices when you get there
/// (within 100 m), then stops. Uses iOS 17's CLBackgroundActivitySession,
/// which works with While Using permission (no "Always"): iOS shows the blue
/// location pill while it runs. Only your arrival time leaves the phone.
///
/// Stops on arrival, at the meet time + 30 minutes, when you tap Stop
/// sharing, or when the plan ends or changes (LeaveBy.cancel).
@MainActor
enum OnMyWayLive {
    /// Refresh the shared time at most this often...
    static let refreshEvery: TimeInterval = 3 * 60
    /// ...or sooner after moving this far.
    static let refreshAfterMeters: CLLocationDistance = 1500
    /// Keep going this long past the meet time (running late).
    static let stopAfterMeet: TimeInterval = 30 * 60

    private static var tasks: [String: Task<Void, Never>] = [:]
    private static var sessions: [String: CLBackgroundActivitySession] = [:]
    /// Which run owns a plan's entries (a stopped run can't clear a newer one).
    private static var runs: [String: UUID] = [:]

    static func install() {
        OnMyWay.liveTracker = { sessionID, destination, meetTime in
            start(sessionID: sessionID, destination: destination, meetTime: meetTime)
        }
        OnMyWay.stopTracker = { stop(sessionID: $0) }
    }

    static var isTracking: Bool { !tasks.isEmpty }

    /// Starts from the foreground (a tap in the app, or the reminder's
    /// "I'm on my way" button, which opens the app): a background session
    /// can't start in the background.
    static func start(sessionID: String, destination: CLLocationCoordinate2D, meetTime: Date) {
        stop(sessionID: sessionID)
        let run = UUID()
        runs[sessionID] = run
        sessions[sessionID] = CLBackgroundActivitySession()
        let place = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let stopAt = meetTime.addingTimeInterval(stopAfterMeet)
        tasks[sessionID] = Task { @MainActor in
            var lastSent = Date()
            var lastSentFrom: CLLocation?
            do {
                for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    if Task.isCancelled || stopAt.timeIntervalSinceNow <= 0 { break }
                    guard let here = update.location, here.horizontalAccuracy >= 0, here.horizontalAccuracy < 200 else { continue }
                    if here.distance(from: place) <= OnMyWay.arrivalMeters {
                        try? await OnMyWay.arrived(sessionID: sessionID)
                        await LiveActivities.arrived(sessionID: sessionID)
                        break
                    }
                    let moved = lastSentFrom.map { here.distance(from: $0) } ?? .greatestFiniteMagnitude
                    guard Date().timeIntervalSince(lastSent) >= refreshEvery
                            || (lastSentFrom != nil && moved >= refreshAfterMeters) else {
                        if lastSentFrom == nil { lastSentFrom = here }
                        continue
                    }
                    lastSent = Date()
                    lastSentFrom = here
                    let eta = await OnMyWay.arrival(from: here.coordinate, to: destination)
                    if !Task.isCancelled { await OnMyWay.refresh(sessionID: sessionID, eta: eta) }
                }
            } catch {
                // Location turned off mid-drive: the last time you shared stays.
            }
            if runs[sessionID] == run { finish(sessionID) }
        }
    }

    static func stop(sessionID: String) {
        tasks[sessionID]?.cancel()
        finish(sessionID)
    }

    private static func finish(_ sessionID: String) {
        runs[sessionID] = nil
        tasks[sessionID] = nil
        sessions[sessionID]?.invalidate()
        sessions[sessionID] = nil
    }
}
