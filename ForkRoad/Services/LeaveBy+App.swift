import Foundation
import CoreLocation
import UIKit
import FirebaseFirestore
import PickerCore

/// The app's side of leave-by: where you are (from AppModel), refreshing
/// reminders when the app opens, and the notification's Directions button.
extension LeaveBy {
    /// Your GPS location if we have it, else the area you're searching.
    static func origin(_ model: AppModel) -> Origin {
        if let gps = model.location.coordinate { return Origin(coordinate: gps, isGPS: true, label: "where you are") }
        return Origin(coordinate: model.center, isGPS: false, label: model.locationName)
    }

    /// Sets up reminders for every recent group that's decided with a time
    /// ahead (and clears ones that ended or changed). Run when the app opens,
    /// so you get reminded even if you never opened the group after the time was set.
    static func refreshAll(_ model: AppModel) async {
        guard FirebaseSetup.isConfigured, (try? await GroupService.shared.userID()) != nil else { return }
        for id in SharedCache.recentSessionIDs().prefix(5) {
            guard let session = try? await GroupService.shared.sessionRef(id).getDocument(as: GroupSession.self),
                  session.status == .decided, let winner = session.winner,
                  let meet = session.meetTime, meet > .now else {
                cancel(sessionID: id)
                continue
            }
            let from = origin(model)
            if let plan = await plan(to: CLLocationCoordinate2D(latitude: winner.latitude, longitude: winner.longitude),
                                     meetTime: meet, from: from.coordinate, isGPS: from.isGPS) {
                await schedule(plan, sessionID: id, winner: winner, mayAsk: false)
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
