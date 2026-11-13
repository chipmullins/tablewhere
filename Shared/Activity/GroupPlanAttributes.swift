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
    /// Also sent by the server in APNs pushes (push-to-start, updates,
    /// end; web/functions/src/liveActivities.ts), so field names and types
    /// must match there. Dates are seconds since 2001 (Swift's default).
    struct ContentState: Codable, Hashable {
        let meetTime: Date
        /// When to leave (already includes the parking buffer). Equal to
        /// `meetTime` when the drive time isn't known (`travelMinutes` 0).
        let leaveAt: Date
        /// Drive time, in whole minutes. 0: not worked out yet.
        let travelMinutes: Int
        /// Friends' "On my way" arrival times (1.1). Nil from older builds.
        var arrivals: [Arrival]? = nil
    }

    /// One friend's arrival time, shared with "On my way" (never a location).
    struct Arrival: Codable, Hashable {
        let name: String
        /// Expected arrival; nil for "I'll text you" late.
        let eta: Date?
        /// "onTheWay", "late", or "arrived".
        let status: String
    }

    let sessionID: String
    /// The group's name ("Friday dinner").
    let title: String
    /// The winning place's name.
    let place: String

    /// How long the activity stays up after the meet time by default (the
    /// "Remove from Lock Screen" setting can make it 0 or 60 minutes).
    static let lingerAfterMeet: TimeInterval = 30 * 60
    /// The longest it can stay ("1 hour after").
    static let maxLingerAfterMeet: TimeInterval = 60 * 60

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
    /// The drive time is known (a leave-by time to count down to).
    var knowsDrive: Bool { travelMinutes > 0 }

    /// "Sam ~7:05 · Alex arrived · Jo running late", or nil with nobody on the way.
    func arrivalsLine() -> String? {
        guard let arrivals, !arrivals.isEmpty else { return nil }
        let parts = arrivals.prefix(3).map { a -> String in
            let first = a.name.split(separator: " ").first.map(String.init) ?? a.name
            switch a.status {
            case "arrived": return "\(first) arrived"
            case "late":
                if let eta = a.eta { return "\(first) late ~\(eta.formatted(date: .omitted, time: .shortened))" }
                return "\(first) running late"
            default:
                if let eta = a.eta { return "\(first) ~\(eta.formatted(date: .omitted, time: .shortened))" }
                return "\(first) on the way"
            }
        }
        let more = arrivals.count - parts.count
        return parts.joined(separator: " · ") + (more > 0 ? " +\(more)" : "")
    }

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
