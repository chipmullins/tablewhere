import SwiftUI
import WidgetKit
import ActivityKit

/// "Leave by 6:42" for a decided group plan, on the Lock Screen and in the
/// Dynamic Island. The app starts and ends it (ForkRoad/Services/LiveActivities.swift).
struct GroupPlanLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GroupPlanAttributes.self) { context in
            GroupPlanLockScreenView(attributes: context.attributes, state: context.state,
                                    phase: context.state.phase(isStale: context.isStale))
                .activityBackgroundTint(Theme.night)
                .activitySystemActionForegroundColor(Theme.text)
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
                    Text(GroupPlanText.detail(context.attributes, state, phase))
                        .font(Theme.body(13, .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: phase == .countdown ? "clock.fill" : "car.fill")
                    .foregroundStyle(Theme.saffron)
            } compactTrailing: {
                GroupPlanCountdown(state: state, phase: phase, short: true)
                    .font(Theme.body(14, .bold))
                    .foregroundStyle(Theme.saffron)
                    .multilineTextAlignment(.trailing)
                    // Timer text otherwise claims all the width it can.
                    .frame(maxWidth: 52, alignment: .trailing)
            } minimal: {
                Image(systemName: phase == .countdown ? "clock.fill" : "car.fill")
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
        HStack(alignment: .center, spacing: 12) {
            GroupPlanBadge(phase: phase, size: 46)
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
                Text(GroupPlanText.detail(attributes, state, phase))
                    .font(Theme.body(13, .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(GroupPlanText.headline(state, phase))
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                GroupPlanCountdown(state: state, phase: phase)
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.accentText)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
        }
        .padding(16)
    }
}

// MARK: - Pieces

/// The saffron tile: a clock before leave-by, a car after.
private struct GroupPlanBadge: View {
    let phase: GroupPlanAttributes.ContentState.Phase
    let size: CGFloat

    var body: some View {
        Image(systemName: phase == .countdown ? "clock.badge" : "car.fill")
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
        case .countdown:
            // Counts down to leave-by; the stale date redraws it as "Go" when it hits zero.
            Text(state.leaveAt, style: .timer)
                .monospacedDigit()
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

    /// "Leave by 6:42 PM" / "Time to go" / "Meet time".
    static func headline(_ state: GroupPlanAttributes.ContentState,
                         _ phase: GroupPlanAttributes.ContentState.Phase) -> String {
        switch phase {
        case .countdown: return "Leave by \(time(state.leaveAt))"
        case .timeToGo: return "Time to go"
        case .arrived: return "Meet time"
        }
    }

    /// "Meet at 7:00 PM · 17 min drive".
    static func detail(_ attributes: GroupPlanAttributes, _ state: GroupPlanAttributes.ContentState,
                       _ phase: GroupPlanAttributes.ContentState.Phase) -> String {
        switch phase {
        case .countdown, .timeToGo:
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
}
