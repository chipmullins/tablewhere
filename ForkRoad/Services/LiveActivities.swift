import Foundation
import ActivityKit
import PickerCore

/// Starts, updates, and ends the group plan Live Activity (drawn by the widget
/// extension; see GroupPlanAttributes). App-only: Live Activities can only be
/// requested by the app, so LeaveBy reaches this through its `activityUpdate`
/// and `activityEnd` hooks, which `install()` sets at launch.
@MainActor
enum LiveActivities {
    typealias State = GroupPlanAttributes.ContentState

    /// Connects LeaveBy's schedule/cancel to Live Activities. Call once at launch.
    static func install() {
        LeaveBy.activityUpdate = { plan, sessionID, winner, title in
            Task { await show(plan, sessionID: sessionID, winner: winner, title: title) }
        }
        LeaveBy.activityEnd = { sessionID in
            Task { await end(sessionID: sessionID) }
        }
        Task { await tidyUp() }
    }

    // MARK: Showing

    /// Starts the activity for a group, or updates it with a new plan.
    /// Ends it instead when the reminder switch is off or the plan is over.
    static func show(_ plan: LeaveBy.Plan, sessionID: String, winner: GroupOption, title: String?) async {
        let endAt = plan.meetTime.addingTimeInterval(GroupPlanAttributes.lingerAfterMeet)
        guard LeaveBy.remindersOn, endAt.timeIntervalSinceNow > 0 else {
            await end(sessionID: sessionID)
            return
        }
        guard plan.meetTime.timeIntervalSinceNow > 0 else {
            // Already past the meet time: leave it up until meet + 30 min.
            await finish(sessionID: sessionID)
            return
        }

        let state = State(meetTime: plan.meetTime, leaveAt: plan.leaveAt, travelMinutes: plan.driveMinutes)
        let content = ActivityContent(state: state, staleDate: state.staleDate(), relevanceScore: 100)
        var current = running(sessionID)

        // A different place (re-decided group): start over so the name is right.
        if let first = current.first, first.attributes.place != winner.name {
            for activity in current { await activity.end(nil, dismissalPolicy: .immediate) }
            current = []
        }

        if let activity = current.first {
            // Extras from a race between two refreshes.
            for extra in current.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            if activity.content.state != state { await activity.update(content) }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            // iOS keeps a Live Activity for about 8 hours, so one started for a
            // plan days out would vanish before dinner. Start it only in the
            // last few hours; opening the app (or the leave-by reminder) then starts it.
            guard plan.leaveAt.timeIntervalSinceNow < Self.startWindow else { return }
            let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let attributes = GroupPlanAttributes(sessionID: sessionID,
                                                 title: name.isEmpty ? "Group plan" : name,
                                                 place: winner.name)
            // Fails when the app isn't in the foreground; the next refresh tries again.
            _ = try? Activity<GroupPlanAttributes>.request(attributes: attributes, content: content, pushType: nil)
        }
        scheduleTimers(sessionID: sessionID, state: state)
    }

    // MARK: Ending

    /// Takes the group's activity down now (group ended, reopened, left, or reminders off).
    static func end(sessionID: String) async {
        timers[sessionID]?.cancel()
        timers[sessionID] = nil
        for activity in Activity<GroupPlanAttributes>.activities where activity.attributes.sessionID == sessionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// At the meet time: ends the activity but leaves it on the Lock Screen
    /// until meet + 30 min, when the system removes it (even if the app isn't running).
    static func finish(sessionID: String) async {
        timers[sessionID]?.cancel()
        timers[sessionID] = nil
        for activity in running(sessionID) {
            let state = activity.content.state
            let endAt = state.meetTime.addingTimeInterval(GroupPlanAttributes.lingerAfterMeet)
            guard endAt.timeIntervalSinceNow > 0 else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            await activity.end(ActivityContent(state: state, staleDate: endAt), dismissalPolicy: .after(endAt))
        }
    }

    /// Finishes activities whose meet time has passed. Run at launch and on each refresh.
    static func tidyUp() async {
        for activity in Activity<GroupPlanAttributes>.activities {
            let state = activity.content.state
            if state.meetTime.addingTimeInterval(GroupPlanAttributes.lingerAfterMeet).timeIntervalSinceNow <= 0 {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else if state.meetTime.timeIntervalSinceNow <= 0 {
                await finish(sessionID: activity.attributes.sessionID)
            }
        }
    }

    // MARK: Helpers

    /// The group's activities that can still be updated.
    private static func running(_ sessionID: String) -> [Activity<GroupPlanAttributes>] {
        Activity<GroupPlanAttributes>.activities.filter {
            $0.attributes.sessionID == sessionID && ($0.activityState == .active || $0.activityState == .stale)
        }
    }

    /// How long before leave-by a Live Activity may start (under iOS's ~8-hour limit).
    static let startWindow: TimeInterval = 6 * 60 * 60

    private static var timers: [String: Task<Void, Never>] = [:]

    /// While the app is running: redraw at leave-by (moving the stale date on
    /// to the meet time), then finish at the meet time. When the app isn't
    /// running the stale date does the first, and the next launch the second.
    private static func scheduleTimers(sessionID: String, state: State) {
        timers[sessionID]?.cancel()
        timers[sessionID] = Task { @MainActor in
            if state.leaveAt.timeIntervalSinceNow > 0 {
                guard await sleep(until: state.leaveAt) else { return }
                for activity in running(sessionID) where activity.content.state == state {
                    await activity.update(ActivityContent(state: state, staleDate: state.staleDate()))
                }
            }
            guard await sleep(until: state.meetTime) else { return }
            await finish(sessionID: sessionID)
        }
    }

    /// Sleeps until `date`. False if the wait was cancelled.
    private static func sleep(until date: Date) async -> Bool {
        let wait = date.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        return !Task.isCancelled
    }
}
