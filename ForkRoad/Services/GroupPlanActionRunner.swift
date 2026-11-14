import Foundation
import CoreLocation
import PickerCore

/// What the Lock Screen countdown's buttons do (GroupPlanActionIntent, a
/// LiveActivityIntent: iOS runs it here in the app, often in the background,
/// without opening Tablewhere).
///
/// The button's new state shows right away; then the arrival time is shared
/// like the in-app "On my way". From the Lock Screen it's a one-time time:
/// live updates while driving start only when the app is in front.
@MainActor
enum GroupPlanActionRunner {
    static func run(_ action: GroupPlanAction, sessionID: String) async {
        guard FirebaseSetup.configureIfPossible() else { return }
        // Feels instant: the buttons change before the network work.
        let status: String = switch action {
        case .onMyWay: "onTheWay"
        case .late10, .late15: "late"
        case .arrived: "arrived"
        }
        let previous = await LiveActivities.setMyStatus(sessionID: sessionID, status)

        _ = try? await GroupService.shared.userID()
        guard let session = try? await GroupService.shared.fetchSession(sessionID),
              session.status == .decided,
              let winner = session.winner,
              let meet = session.meetTime else {
            // Nothing was shared (offline, or the plan changed): put the buttons back.
            await LiveActivities.setMyStatus(sessionID: sessionID, previous)
            return
        }
        switch action {
        case .onMyWay:
            // No location prompt from the Lock Screen (none can show while the
            // app is in the background): without permission it shares no time.
            _ = try? await OnMyWay.start(sessionID: sessionID,
                                         destination: CLLocationCoordinate2D(latitude: winner.latitude,
                                                                             longitude: winner.longitude),
                                         meetTime: meet, askForLocation: false)
        case .late10:
            try? await OnMyWay.runningLate(sessionID: sessionID, minutes: 10, meetTime: meet)
        case .late15:
            try? await OnMyWay.runningLate(sessionID: sessionID, minutes: 15, meetTime: meet)
        case .arrived:
            try? await OnMyWay.arrived(sessionID: sessionID)
        }
    }
}
