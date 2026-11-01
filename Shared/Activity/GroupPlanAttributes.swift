import Foundation
import ActivityKit

/// The group plan Live Activity: "Leave by 6:42" on the Lock Screen and in the
/// Dynamic Island once a group has a place, a meet time, and this phone has a
/// leave-by plan.
///
/// Compiled by the app (which starts, updates, and ends it, in
/// ForkRoad/Services/LiveActivities.swift) and by the widget extension (which
/// draws it, in ForkRoadWidgets/GroupPlanLiveActivity.swift). Keep this file
/// to Foundation + ActivityKit: no Firebase, no app-only types.
struct GroupPlanAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let meetTime: Date
        /// When to leave (already includes the parking buffer).
        let leaveAt: Date
        /// Drive time, in whole minutes.
        let travelMinutes: Int
    }

    let sessionID: String
    /// The group's name ("Friday dinner").
    let title: String
    /// The winning place's name.
    let place: String

    /// How long the activity stays up after the meet time.
    static let lingerAfterMeet: TimeInterval = 30 * 60

    /// Opens the group in ForkRoad (handled by the app's forkroad://group/<id> link).
    var url: URL? {
        let id = sessionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionID
        return URL(string: "forkroad://group/\(id)")
    }
}

extension GroupPlanAttributes.ContentState {
    enum Phase {
        /// Before leave-by: "Leave by 6:42" with a countdown.
        case countdown
        /// Leave-by has passed: "Time to go".
        case timeToGo
        /// The meet time has passed.
        case arrived
    }

    /// Which state to show. `isStale` comes from the activity context: the app
    /// sets the stale date to the leave-by time, so the system redraws the
    /// activity as "Time to go" even if the app isn't running then.
    /// (Compared as seconds, not with Date's operators; see LeaveBy.Plan.)
    func phase(isStale: Bool, now: Date = Date()) -> Phase {
        if meetTime.timeIntervalSince(now) <= 0 { return .arrived }
        if isStale || leaveAt.timeIntervalSince(now) <= 0 { return .timeToGo }
        return .countdown
    }

    /// When the system should redraw this state next (see `phase`).
    func staleDate(now: Date = Date()) -> Date {
        if leaveAt.timeIntervalSince(now) > 0 { return leaveAt }
        if meetTime.timeIntervalSince(now) > 0 { return meetTime }
        return meetTime.addingTimeInterval(GroupPlanAttributes.lingerAfterMeet)
    }
}
