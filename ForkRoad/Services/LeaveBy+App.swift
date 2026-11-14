import Foundation
import CoreLocation
import UIKit
import FirebaseFirestore
import PickerCore

/// The app's side of leave-by: where you are (from AppModel), refreshing
/// reminders when the app opens, and the notification's Directions button.
extension LeaveBy {
    /// Your GPS location if we have it, else the area you're searching.
    /// Nil before ForkRoad knows either.
    static func origin(_ model: AppModel) -> Origin? {
        if let gps = model.location.coordinate { return Origin(coordinate: gps, isGPS: true, label: "where you are") }
        guard model.hasLocation else { return nil }
        return Origin(coordinate: model.center, isGPS: false, label: model.locationName)
    }

    /// Sets up reminders for every recent group that's decided with a time
    /// ahead (and clears ones that ended or changed). Run when the app opens,
    /// so you get reminded even if you never opened the group after the time was set.
    static func refreshAll(_ model: AppModel) async {
        // Take down Live Activities whose meet time has passed, even offline.
        await LiveActivities.tidyUp()
        guard FirebaseSetup.isConfigured, (try? await GroupService.shared.userID()) != nil else { return }
        for id in SharedCache.recentSessionIDs().prefix(5) {
            // Offline? Leave existing reminders alone rather than cancelling them.
            guard let snapshot = try? await GroupService.shared.sessionRef(id).getDocument() else { continue }
            // Ended by its creator: stop checking it (and copying settings to it).
            if !snapshot.exists {
                cancel(sessionID: id)
                SharedCache.forgetSession(id)
                continue
            }
            guard let session = try? snapshot.data(as: GroupSession.self),
                  session.status == .decided, let winner = session.winner,
                  let meet = session.meetTime,
                  // Not before "On my way" is done (meet + 30 min, running late).
                  meet.timeIntervalSinceNow > -max(LiveActivities.linger, OnMyWayLive.stopAfterMeet) else {
                cancel(sessionID: id)
                continue
            }
            // Just past the meet time: nothing left to remind about, but the
            // Live Activity stays on the Lock Screen for the chosen time.
            guard meet.timeIntervalSinceNow > 0 else {
                await LiveActivities.finish(sessionID: id)
                continue
            }
            guard let from = origin(model) else { continue }
            if let plan = await plan(to: CLLocationCoordinate2D(latitude: winner.latitude, longitude: winner.longitude),
                                     meetTime: meet, from: from.coordinate, isGPS: from.isGPS) {
                await schedule(plan, sessionID: id, winner: winner, title: session.title, mayAsk: false)
            }
        }
    }

    /// The notification's Directions button.
    static func openDirections(from info: [AnyHashable: Any]) {
        guard let lat = info["lat"] as? Double, let lon = info["lon"] as? Double else { return }
        let name = (info["name"] as? String)?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://maps.apple.com/?daddr=\(lat),\(lon)&q=\(name)&dirflg=d") {
            UIApplication.shared.open(url)
        }
    }
}
