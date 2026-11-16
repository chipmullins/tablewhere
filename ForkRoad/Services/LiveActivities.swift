import Foundation
import ActivityKit
import PickerCore

/// Starts, updates, and ends the group plan Live Activity (drawn by the widget
/// extension; see GroupPlanAttributes). App-only: LeaveBy reaches this
/// through its `activityUpdate` and `activityEnd` hooks, which `install()`
/// sets at launch.
///
/// 1.1: the server starts it too (push-to-start, iOS 17.2+) at the chosen
/// lead time, updates it (friends' "On my way" times), and ends it on time,
/// even if the app never opens (web/functions/src/liveActivities.ts). This
/// file hands the server the tokens it needs: the device's push-to-start
/// token, and each running activity's own push token.
@MainActor
enum LiveActivities {
    typealias State = GroupPlanAttributes.ContentState

    /// Connects LeaveBy's schedule/cancel to Live Activities, and starts
    /// watching for push tokens. Call once at launch.
    static func install() {
        LeaveBy.activityUpdate = { plan, sessionID, winner, title in
            Task { await show(plan, sessionID: sessionID, winner: winner, title: title) }
        }
        LeaveBy.activityEnd = { sessionID in
            Task { await end(sessionID: sessionID) }
        }
        OnMyWay.onArrived = { sessionID in
            Task { await arrived(sessionID: sessionID) }
        }
        LiveActivitySettings.activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        // Activities already up (started by the app or by a push): their tokens.
        for activity in Activity<GroupPlanAttributes>.activities { watchToken(of: activity) }
        Task {
            for await activity in Activity<GroupPlanAttributes>.activityUpdates {
                // A push-started one and the app's own can race into two:
                // keep the one already up, and point the server back at it.
                let others = running(activity.attributes.sessionID).filter { $0.id != activity.id }
                if let kept = others.first {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    if let token = tokens[kept.id] {
                        await GroupService.shared.saveActivityToken(sessionID: kept.attributes.sessionID, token: token,
                                                                    meetTime: kept.content.state.meetTime)
                    }
                    continue
                }
                watchToken(of: activity)
            }
        }
        Task {
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                guard LiveActivitySettings.activitiesEnabled != enabled else { continue }
                LiveActivitySettings.activitiesEnabled = enabled
                await GroupService.shared.saveDeviceEverywhere()
            }
        }
        if #available(iOS 17.2, *) {
            Task {
                for await data in Activity<GroupPlanAttributes>.pushToStartTokenUpdates {
                    let hex = hexString(data)
                    guard LiveActivitySettings.startToken != hex else { continue }
                    LiveActivitySettings.startToken = hex
                    await GroupService.shared.saveDeviceEverywhere()
                }
            }
        }
        Task { await tidyUp() }
    }

    // MARK: Showing

    /// Starts the activity for a group, or updates it with a new plan.
    /// Ends it instead when the reminder switch is off or the plan is over.
    static func show(_ plan: LeaveBy.Plan, sessionID: String, winner: GroupOption, title: String?) async {
        let endAt = plan.meetTime.addingTimeInterval(linger)
        guard LeaveBy.remindersOn, endAt.timeIntervalSinceNow > 0 else {
            await end(sessionID: sessionID)
            return
        }
        // Everyone's already at the table: the countdown is done for this plan.
        guard !LiveActivitySettings.isAllHere(sessionID, meetTime: plan.meetTime) else { return }
        guard plan.meetTime.timeIntervalSinceNow > 0 else {
            // Already past the meet time: leave it up until the chosen time.
            await finish(sessionID: sessionID)
            return
        }

        var current = running(sessionID)
        // Keep friends' arrival times (and yours) the server put there.
        let old = current.first?.content.state
        var state = State(meetTime: plan.meetTime, leaveAt: plan.leaveAt, travelMinutes: plan.driveMinutes,
                          arrivals: old?.arrivals)
        state.myStatus = old?.myStatus
        state.expected = old?.expected
        state.allHere = old?.allHere
        let content = ActivityContent(state: state, staleDate: state.staleDate(), relevanceScore: 100)

        // A different place (re-decided group): start over so the name is right.
        if let first = current.first, first.attributes.place != winner.name {
            for activity in current { await activity.end(nil, dismissalPolicy: .immediate) }
            current = []
        }

        if let activity = current.first {
            // Extras from a race between two refreshes (or the app and a push).
            for extra in current.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            if activity.content.state != state { await activity.update(content) }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            // Only within the chosen lead time (see `shouldStart`). Earlier,
            // the server starts it on time (or the heads-up reminder asks you to open the app).
            guard Self.shouldStart(plan) else { return }
            let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let attributes = GroupPlanAttributes(sessionID: sessionID,
                                                 title: name.isEmpty ? "Group plan" : name,
                                                 place: winner.name)
            // Fails when the app isn't in the foreground; the next refresh tries again.
            // With a push token, so the server can update and end it.
            if let activity = try? Activity<GroupPlanAttributes>.request(attributes: attributes, content: content,
                                                                         pushType: .token) {
                watchToken(of: activity)
                // Tells the server this phone has it, so it doesn't start a second one.
                await GroupService.shared.saveActivityToken(sessionID: sessionID, token: nil, meetTime: plan.meetTime)
            }
        }
        scheduleTimers(sessionID: sessionID, state: state)
    }

    /// Friends' "On my way" times, your own status, and how many are
    /// coming, while the app is open (pushes do this otherwise). When
    /// everyone's there, it shows "All 4 here" for a minute, then goes.
    static func updateArrivals(sessionID: String, _ arrivals: [GroupPlanAttributes.Arrival],
                               myStatus: String?, expected: Int?) async {
        await mutate(sessionID) { state in
            state.arrivals = arrivals.isEmpty ? nil : arrivals
            state.myStatus = myStatus
            state.expected = expected
        }
    }

    /// A Lock Screen button was tapped: show the new buttons right away.
    /// Returns the status it replaced, to put back if sharing fails.
    @discardableResult
    static func setMyStatus(sessionID: String, _ status: String?) async -> String? {
        let old = running(sessionID).first?.content.state.myStatus
        await mutate(sessionID) { $0.myStatus = status }
        return old
    }

    /// Everyone's at the table: "All 4 here ✓", then off the Lock Screen in a minute.
    static let allHereLinger: TimeInterval = 60

    /// Applies a change; if that makes everyone here, ends with "All N here ✓"
    /// (checked on the new state itself, not a re-read).
    private static func mutate(_ sessionID: String, _ change: (inout State) -> Void) async {
        for activity in running(sessionID) {
            var state = activity.content.state
            change(&state)
            if let expected = state.expected, expected > 1, state.hereCount >= expected {
                state.allHere = true
                LiveActivitySettings.markAllHere(sessionID, meetTime: state.meetTime)
                timers[sessionID]?.cancel()
                timers[sessionID] = nil
                let goAt = Date().addingTimeInterval(allHereLinger)
                await activity.end(ActivityContent(state: state, staleDate: goAt), dismissalPolicy: .after(goAt))
                continue
            }
            guard state != activity.content.state else { continue }
            await activity.update(ActivityContent(state: state, staleDate: state.staleDate()))
        }
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

    /// "On my way" saw you arrive: with "Remove from Lock Screen: When I
    /// arrive", it goes now.
    static func arrived(sessionID: String) async {
        guard LiveActivitySettings.removal == .arrive else { return }
        // "All 4 here ✓" is showing its last minute: let it.
        guard !Activity<GroupPlanAttributes>.activities.contains(where: {
            $0.attributes.sessionID == sessionID && $0.content.state.isAllHere
        }) else { return }
        await end(sessionID: sessionID)
    }

    /// How long it stays after the meet time ("Remove from Lock Screen").
    static var linger: TimeInterval { LiveActivitySettings.removal.linger }

    /// Past the meet time: the countdown stays ACTIVE until the chosen
    /// removal time, so its buttons (Late +10, I'm here) and friends'
    /// arrivals keep working while people are still getting there. It only
    /// ends early once you've arrived or everyone's here. The server's end
    /// push takes it down on time when the app isn't running; this timer
    /// does when it is.
    static func finish(sessionID: String) async {
        timers[sessionID]?.cancel()
        timers[sessionID] = nil
        var endAtForTimer: Date?
        for activity in running(sessionID) {
            let state = activity.content.state
            let endAt = state.meetTime.addingTimeInterval(linger)
            guard endAt.timeIntervalSinceNow > 0 else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            if state.myStatus == "arrived" || state.isAllHere {
                await activity.end(ActivityContent(state: state, staleDate: endAt), dismissalPolicy: .after(endAt))
            } else {
                await activity.update(ActivityContent(state: state, staleDate: endAt))
                endAtForTimer = endAt
            }
        }
        if let endAt = endAtForTimer {
            timers[sessionID] = Task { @MainActor in
                guard await sleep(until: endAt) else { return }
                await end(sessionID: sessionID)
            }
        }
    }

    /// Finishes activities whose meet time has passed. Run at launch and on each refresh.
    static func tidyUp() async {
        for activity in Activity<GroupPlanAttributes>.activities {
            let state = activity.content.state
            if state.meetTime.addingTimeInterval(linger).timeIntervalSinceNow <= 0 {
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

    /// Starts at the chosen lead time before the meet time ("Lock Screen
    /// countdown starts", default 2 hours), or 15 minutes before leave-by
    /// for a longer drive, whichever comes first. iOS caps them at ~8 hours.
    static let startBeforeLeave: TimeInterval = 15 * 60

    static func shouldStart(_ plan: LeaveBy.Plan) -> Bool {
        plan.meetTime.timeIntervalSinceNow <= LiveActivitySettings.lead
            || plan.leaveAt.timeIntervalSinceNow <= startBeforeLeave
    }

    /// Activities whose push token we're already watching, and their latest tokens.
    private static var watched: Set<String> = []
    private static var tokens: [String: String] = [:]

    /// Saves each activity's push token to its plan (it can change; iOS
    /// sends a new one), so the server can update and end it.
    private static func watchToken(of activity: Activity<GroupPlanAttributes>) {
        guard watched.insert(activity.id).inserted else { return }
        Task { @MainActor in
            for await data in activity.pushTokenUpdates {
                let hex = hexString(data)
                tokens[activity.id] = hex
                await GroupService.shared.saveActivityToken(sessionID: activity.attributes.sessionID,
                                                            token: hex,
                                                            meetTime: activity.content.state.meetTime)
            }
        }
    }

    /// Saves each running activity's token again. A token that arrived while
    /// the phone was locked (a push-started countdown) couldn't be saved then;
    /// run when the app opens so the server can still update and end it.
    static func resaveTokens() async {
        for activity in Activity<GroupPlanAttributes>.activities
        where activity.activityState == .active || activity.activityState == .stale {
            guard let token = tokens[activity.id] else { continue }
            await GroupService.shared.saveActivityToken(sessionID: activity.attributes.sessionID, token: token,
                                                        meetTime: activity.content.state.meetTime)
        }
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static var timers: [String: Task<Void, Never>] = [:]

    /// While the app is running: redraw at leave-by (moving the stale date on
    /// to the meet time), then finish at the meet time. When the app isn't
    /// running the stale date does the first, and the server's end push the second.
    private static func scheduleTimers(sessionID: String, state: State) {
        timers[sessionID]?.cancel()
        timers[sessionID] = Task { @MainActor in
            if state.leaveAt.timeIntervalSinceNow > 0 {
                guard await sleep(until: state.leaveAt) else { return }
                for activity in running(sessionID) where activity.content.state.meetTime.timeIntervalSinceReferenceDate
                    == state.meetTime.timeIntervalSinceReferenceDate {
                    let now = activity.content.state
                    await activity.update(ActivityContent(state: now, staleDate: now.staleDate()))
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
