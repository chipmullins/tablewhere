import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

/// "Leave by 6:42" for a decided group plan, on the Lock Screen and in the
/// Dynamic Island. The app and the server start and end it
/// (ForkRoad/Services/LiveActivities.swift, web/functions/src/liveActivities.ts).
/// 1.1: buttons for On my way / Running late / I'm here (GroupPlanActionIntent),
/// friends' arrivals ("2/4 here"), and "Everyone's here" at the end.
struct GroupPlanLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GroupPlanAttributes.self) { context in
            GroupPlanLockScreenView(attributes: context.attributes, state: context.state,
                                    phase: context.state.phase(isStale: context.isStale))
                // Always the dark look: Theme.night follows light/dark, and on
                // a light Lock Screen it turned see-through with faded text.
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(Color(red: 11 / 255, green: 11 / 255, blue: 15 / 255).opacity(0.92))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            let state = context.state
            let phase = state.phase(isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GroupPlanBadge(phase: phase, size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GroupPlanCountdown(state: state, phase: phase)
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.saffron)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 96, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(context.attributes.place)
                            .font(Theme.display(17))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(GroupPlanText.headline(state, phase))
                            .font(Theme.body(13, .semibold))
                            .foregroundStyle(Theme.saffron)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        Text(state.isAllHere ? GroupPlanText.allHere(state)
                             : state.arrivalsLine() ?? GroupPlanText.detail(context.attributes, state, phase))
                            .font(Theme.body(13, .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                        GroupPlanButtons(sessionID: context.attributes.sessionID, state: state, phase: phase)
                    }
                }
            } compactLeading: {
                Image(systemName: GroupPlanText.compactSymbol(state, phase))
                    .foregroundStyle(Theme.saffron)
            } compactTrailing: {
                GroupPlanCompactTrailing(state: state, phase: phase)
                    .font(Theme.body(14, .bold))
                    .foregroundStyle(Theme.saffron)
                    .multilineTextAlignment(.trailing)
                    // Timer text otherwise claims all the width it can.
                    .frame(maxWidth: 52, alignment: .trailing)
            } minimal: {
                Image(systemName: GroupPlanText.compactSymbol(state, phase))
                    .foregroundStyle(Theme.saffron)
            }
            .widgetURL(context.attributes.url)
            .keylineTint(Theme.saffron)
        }
    }
}

// MARK: - Lock Screen

private struct GroupPlanLockScreenView: View {
    let attributes: GroupPlanAttributes
    let state: GroupPlanAttributes.ContentState
    let phase: GroupPlanAttributes.ContentState.Phase

    var body: some View {
        VStack(spacing: 8) {
            summary
            GroupPlanButtons(sessionID: attributes.sessionID, state: state, phase: phase)
        }
        .padding(14)
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 12) {
            GroupPlanBadge(phase: phase, size: 46, allHere: state.isAllHere)
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.title.uppercased())
                    .font(Theme.body(11, .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.accentText)
                    .lineLimit(1)
                Text(attributes.place)
                    .font(Theme.display(19))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // Lock Screen activities top out at 160 pt: with friends' times
                // showing, they replace the drive line.
                if state.isAllHere || state.arrivalsLine() == nil {
                    Text(state.isAllHere ? GroupPlanText.allHere(state) : GroupPlanText.detail(attributes, state, phase))
                        .font(Theme.body(13, .medium))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                // Friends' "On my way" times (arrival times only, never locations).
                if !state.isAllHere, let line = state.arrivalsLine() {
                    Label(line, systemImage: "car.fill")
                        .font(Theme.body(12, .semibold))
                        .foregroundStyle(Theme.accentText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(GroupPlanText.headline(state, phase))
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(GroupPlanText.isUrgent(state, phase) ? Color.orange : Theme.text)
                    .lineLimit(1)
                GroupPlanCountdown(state: state, phase: phase)
                    .font(Theme.display(24))
                    .foregroundStyle(GroupPlanText.isUrgent(state, phase) ? Color.orange : Theme.accentText)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
        }
    }
}

// MARK: - Buttons (iOS 17 interactive Live Activities)

/// On my way → Late +10 / +15 / I'm here. They run GroupPlanActionIntent in
/// the app without opening it. Gone once you've arrived or everyone's there.
private struct GroupPlanButtons: View {
    let sessionID: String
    let state: GroupPlanAttributes.ContentState
    let phase: GroupPlanAttributes.ContentState.Phase

    var body: some View {
        if !state.isAllHere && state.myStatus != "arrived" {
            HStack(spacing: 8) {
                if state.hasNotLeft {
                    if phase != .arrived {
                        button("I’m on my way", "car.fill", .onMyWay, primary: true)
                    }
                    // Past leave-by (or the meet time) and still home: offer late.
                    if phase != .countdown {
                        button("Late +10", "clock.badge.exclamationmark", .late10)
                    }
                    if phase == .arrived {
                        button("I’m here", "checkmark.circle.fill", .arrived, primary: true)
                    }
                } else {
                    button("+10", "clock.badge.exclamationmark", .late10)
                    button("+15", "clock.badge.exclamationmark", .late15)
                    button("I’m here", "checkmark.circle.fill", .arrived, primary: true)
                }
            }
        }
    }

    private func button(_ title: String, _ symbol: String, _ action: GroupPlanAction, primary: Bool = false) -> some View {
        Button(intent: GroupPlanActionIntent(sessionID: sessionID, action: action)) {
            Label(title, systemImage: symbol)
                .font(Theme.body(13, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(primary ? Theme.onSaffron : Color.white)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(primary ? Theme.saffron : Color.white.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.spoken(action, title))
    }

    /// "+10" alone means little to VoiceOver.
    private static func spoken(_ action: GroupPlanAction, _ title: String) -> String {
        switch action {
        case .late10: return "Running 10 minutes late"
        case .late15: return "Running 15 minutes late"
        case .onMyWay: return "I’m on my way"
        case .arrived: return "I’m here"
        }
    }
}

/// The Dynamic Island's right side: "2/4" once people arrive, else the next
/// friend's time, else your countdown.
private struct GroupPlanCompactTrailing: View {
    let state: GroupPlanAttributes.ContentState
    let phase: GroupPlanAttributes.ContentState.Phase

    var body: some View {
        if state.isAllHere {
            Text("All ✓")
        } else if let here = state.hereLabel {
            Text(here).monospacedDigit()
        } else if !state.hasNotLeft || phase != .countdown, let next = state.nextArrival, let eta = next.eta {
            Text(GroupPlanText.shortTime(eta)).monospacedDigit()
        } else {
            GroupPlanCountdown(state: state, phase: phase, short: true)
        }
    }
}

// MARK: - Pieces

/// The saffron tile: a clock before leave-by, a car after.
private struct GroupPlanBadge: View {
    let phase: GroupPlanAttributes.ContentState.Phase
    let size: CGFloat
    var allHere = false

    var body: some View {
        Image(systemName: allHere ? "checkmark" : phase == .countdown ? "clock.badge" : "car.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Theme.onSaffron)
            .frame(width: size, height: size)
            .background(Theme.saffron, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// The ticking countdown to leave-by, or a word once it's passed.
private struct GroupPlanCountdown: View {
    let state: GroupPlanAttributes.ContentState
    let phase: GroupPlanAttributes.ContentState.Phase
    var short = false

    var body: some View {
        switch phase {
        case .countdown, .timeToGo where !state.hasNotLeft:
            // On your way (or late): count down to the meet time, not leave-by.
            if !state.hasNotLeft {
                Text(state.meetTime, style: .timer)
                    .monospacedDigit()
            } else {
                // Counts down to leave-by; the stale date redraws it as "Leave now" at zero.
                Text(state.leaveAt, style: .timer)
                    .monospacedDigit()
            }
        case .timeToGo where state.hasNotLeft:
            Text(short ? "Now" : "Leave now")
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        case .timeToGo:
            Text(short ? "Go" : "Time to go")
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        case .arrived:
            Text(GroupPlanText.time(state.meetTime))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

enum GroupPlanText {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Leave by 6:42 PM" / "Time to go" / "Meet time" ("Meet at 7:00 PM"
    /// when the drive time isn't known yet).
    static func headline(_ state: GroupPlanAttributes.ContentState,
                         _ phase: GroupPlanAttributes.ContentState.Phase) -> String {
        if state.isAllHere { return "Everyone’s here" }
        switch state.myStatus {
        case "arrived": return "You’re here"
        case "late": return "Late · meet in"
        case "onTheWay": return "On your way · meet in"
        default: break
        }
        switch phase {
        case .timeToGo where state.hasNotLeft: return "Leave now"
        case .countdown where !state.knowsDrive: return "Meet at \(time(state.meetTime))"
        case .countdown: return "Leave by \(time(state.leaveAt))"
        case .timeToGo: return "Time to go"
        case .arrived: return "Meet time"
        }
    }

    /// Past leave-by and you haven't left: orange.
    static func isUrgent(_ state: GroupPlanAttributes.ContentState,
                         _ phase: GroupPlanAttributes.ContentState.Phase) -> Bool {
        phase == .timeToGo && state.hasNotLeft && !state.isAllHere
    }

    /// "All 4 here. Enjoy!"
    static func allHere(_ state: GroupPlanAttributes.ContentState) -> String {
        if let expected = state.expected, expected > 1 { return "All \(expected) here. Enjoy!" }
        return "Everyone’s here. Enjoy!"
    }

    /// "7:05" (no AM/PM: the compact Dynamic Island is tiny).
    static func shortTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
    }

    static func compactSymbol(_ state: GroupPlanAttributes.ContentState,
                              _ phase: GroupPlanAttributes.ContentState.Phase) -> String {
        if state.isAllHere { return "checkmark.circle.fill" }
        if state.hereLabel != nil { return "person.2.fill" }
        return phase == .countdown ? "clock.fill" : "car.fill"
    }

    /// "Meet at 7:00 PM · 17 min drive".
    static func detail(_ attributes: GroupPlanAttributes, _ state: GroupPlanAttributes.ContentState,
                       _ phase: GroupPlanAttributes.ContentState.Phase) -> String {
        switch phase {
        case .countdown, .timeToGo:
            guard state.knowsDrive else { return "Open Tablewhere for your leave-by time" }
            return "Meet at \(time(state.meetTime)) · \(state.travelMinutes) min drive"
        case .arrived:
            return "Enjoy \(attributes.place)!"
        }
    }
}

#Preview("Lock Screen", as: .content, using: GroupPlanAttributes(sessionID: "preview", title: "Friday dinner",
                                                                  place: "Sora Ramen Bar")) {
    GroupPlanLiveActivity()
} contentStates: {
    GroupPlanAttributes.ContentState(meetTime: .now.addingTimeInterval(40 * 60),
                                     leaveAt: .now.addingTimeInterval(18 * 60), travelMinutes: 17)
    GroupPlanAttributes.ContentState(meetTime: .now.addingTimeInterval(10 * 60),
                                     leaveAt: .now.addingTimeInterval(-2 * 60), travelMinutes: 17)
    GroupPlanAttributes.ContentState(meetTime: .now.addingTimeInterval(10 * 60),
                                     leaveAt: .now.addingTimeInterval(-2 * 60), travelMinutes: 17,
                                     arrivals: [.init(name: "Sam", eta: .now, status: "arrived"),
                                                .init(name: "Alex", eta: .now.addingTimeInterval(300), status: "onTheWay")],
                                     myStatus: "onTheWay", expected: 4)
    GroupPlanAttributes.ContentState(meetTime: .now.addingTimeInterval(-5 * 60),
                                     leaveAt: .now.addingTimeInterval(-20 * 60), travelMinutes: 17,
                                     arrivals: [.init(name: "Sam", eta: .now, status: "arrived")],
                                     myStatus: "arrived", expected: 2, allHere: true)
}
