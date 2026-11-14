import Foundation
import UIKit
import CoreLocation
import PickerCore

/// "On my way", step 2 (1.1): after you tap it, keeps your arrival time
/// fresh while you drive, and notices when you get there (within 100 m),
/// then stops. Uses iOS 17's CLBackgroundActivitySession, which works with
/// While Using permission (no "Always"): iOS shows the blue location pill
/// while it runs. Only your arrival time leaves the phone.
///
/// Writes only when the arrival time moves by 2+ minutes (each write
/// notifies the group's phones). Survives iOS ending the app mid-drive: the
/// run is saved and picked up again at relaunch.
///
/// Stops on arrival, at the meet time + 30 minutes, when you tap Stop
/// sharing, or when the plan ends or changes (LeaveBy.cancel).
@MainActor
enum OnMyWayLive {
    /// Look for a new arrival time at most this often...
    static let refreshEvery: TimeInterval = 3 * 60
    /// ...or sooner after moving this far.
    static let refreshAfterMeters: CLLocationDistance = 5000
    /// ...and share it only if it moved this much.
    static let minETAChange: TimeInterval = 2 * 60
    /// Keep going this long past the meet time (running late).
    static let stopAfterMeet: TimeInterval = 30 * 60

    private static var tasks: [String: Task<Void, Never>] = [:]
    private static var sessions: [String: CLBackgroundActivitySession] = [:]
    /// Which run owns a plan's entries (a stopped run can't clear a newer one).
    private static var runs: [String: UUID] = [:]
    private static var deadlines: [String: Task<Void, Never>] = [:]

    /// Saved runs, to pick up after iOS ends the app: id → [lat, lon, meet].
    private static let savedKey = "onMyWay.liveRuns"

    static func install() {
        OnMyWay.liveTracker = { sessionID, destination, meetTime in
            start(sessionID: sessionID, destination: destination, meetTime: meetTime)
        }
        OnMyWay.stopTracker = { stop(sessionID: $0) }
        // iOS relaunches the app (often in the background) after ending it
        // mid-run: start the saved runs again.
        let saved = UserDefaults.standard.dictionary(forKey: savedKey) as? [String: [Double]] ?? [:]
        for (id, run) in saved where run.count == 3 {
            let meet = Date(timeIntervalSince1970: run[2])
            if meet.addingTimeInterval(stopAfterMeet).timeIntervalSinceNow > 0 {
                start(sessionID: id, destination: CLLocationCoordinate2D(latitude: run[0], longitude: run[1]),
                      meetTime: meet, resuming: true)
            } else {
                forget(id)
            }
        }
    }

    static var isTracking: Bool { !tasks.isEmpty }

    /// Starts from the foreground (a tap in the app, or the reminder's
    /// "I'm on my way" button, which opens the app): a background session
    /// can't start in the background, but one that was running can be
    /// picked up again there (`resuming`).
    static func start(sessionID: String, destination: CLLocationCoordinate2D, meetTime: Date, resuming: Bool = false) {
        // From the Lock Screen buttons the app runs in the background, where
        // a new session can't start: that tap shares a one-time time.
        guard resuming || UIApplication.shared.applicationState != .background else { return }
        stop(sessionID: sessionID)
        let run = UUID()
        runs[sessionID] = run
        sessions[sessionID] = CLBackgroundActivitySession()
        var saved = UserDefaults.standard.dictionary(forKey: savedKey) as? [String: [Double]] ?? [:]
        saved[sessionID] = [destination.latitude, destination.longitude, meetTime.timeIntervalSince1970]
        UserDefaults.standard.set(saved, forKey: savedKey)

        let place = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let stopAt = meetTime.addingTimeInterval(stopAfterMeet)
        tasks[sessionID] = Task { @MainActor in
            var lastChecked = Date()
            var lastCheckedFrom: CLLocation?
            var lastShared: Date? = OnMyWay.lastSharedETA[sessionID]
            do {
                // Default accuracy: enough for a drive time and the 100 m
                // arrival check, far easier on the battery than navigation GPS.
                for try await update in CLLocationUpdate.liveUpdates(.default) {
                    if Task.isCancelled || stopAt.timeIntervalSinceNow <= 0 { break }
                    guard let here = update.location, here.horizontalAccuracy >= 0, here.horizontalAccuracy < 200 else { continue }
                    if here.distance(from: place) <= OnMyWay.arrivalMeters {
                        // Also takes the countdown down ("When I arrive"), via OnMyWay.onArrived.
                        try? await OnMyWay.arrived(sessionID: sessionID)
                        break
                    }
                    guard let from = lastCheckedFrom else { lastCheckedFrom = here; continue }
                    guard Date().timeIntervalSince(lastChecked) >= refreshEvery
                            || here.distance(from: from) >= refreshAfterMeters else { continue }
                    lastChecked = Date()
                    lastCheckedFrom = here
                    guard let eta = await OnMyWay.arrival(from: here.coordinate, to: destination),
                          !Task.isCancelled else { continue }
                    if let lastShared, abs(eta.timeIntervalSince(lastShared)) < minETAChange { continue }
                    lastShared = eta
                    await OnMyWay.refresh(sessionID: sessionID, eta: eta)
                }
            } catch {
                // Location turned off mid-drive: the last time you shared stays.
            }
            if runs[sessionID] == run { finish(sessionID) }
        }
        // Updates stop while you're parked (and never come with location
        // off), so the deadline can't wait for one: stop on time regardless.
        deadlines[sessionID] = Task { @MainActor in
            let wait = stopAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard !Task.isCancelled, runs[sessionID] == run else { return }
            stop(sessionID: sessionID)
        }
    }

    static func stop(sessionID: String) {
        tasks[sessionID]?.cancel()
        deadlines[sessionID]?.cancel()
        deadlines[sessionID] = nil
        finish(sessionID)
    }

    private static func finish(_ sessionID: String) {
        runs[sessionID] = nil
        tasks[sessionID] = nil
        sessions[sessionID]?.invalidate()
        sessions[sessionID] = nil
        forget(sessionID)
    }

    private static func forget(_ sessionID: String) {
        var saved = UserDefaults.standard.dictionary(forKey: savedKey) as? [String: [Double]] ?? [:]
        guard saved.removeValue(forKey: sessionID) != nil else { return }
        UserDefaults.standard.set(saved, forKey: savedKey)
    }
}
