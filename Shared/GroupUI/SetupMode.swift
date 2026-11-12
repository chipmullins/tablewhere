import SwiftUI
import PickerCore

/// How a new group plan decides, as the setup screens offer it (the app and
/// iMessage). "Spin our picks" and "Surprise us" are both `GroupMode.spin`;
/// Surprise us fills the wheel with places nearby instead of everyone's picks.
enum SetupMode: String, CaseIterable, Identifiable {
    case vote, spin, surprise, plan
    var id: Self { self }

    var groupMode: GroupMode {
        switch self {
        case .vote: return .vote
        case .spin, .surprise: return .spin
        case .plan: return .plan
        }
    }

    var title: String {
        switch self {
        case .vote: return "Vote"
        case .spin: return "Spin our picks"
        case .surprise: return "Surprise us"
        case .plan: return "I’ll pick"
        }
    }

    var line: String {
        switch self {
        case .vote: return "Everyone votes on a few places"
        case .spin: return "Everyone adds one place, then the wheel picks"
        case .surprise: return "The wheel picks from places nearby"
        case .plan: return "You choose where and when"
        }
    }

    var icon: String {
        switch self {
        case .vote: return "hand.raised.fill"
        case .spin: return "person.3.fill"
        case .surprise: return "sparkles"
        case .plan: return "mappin.and.ellipse"
        }
    }

    var defaultTitle: String {
        self == .surprise ? "Surprise us" : groupMode.defaultTitle
    }

    var startTitle: String {
        switch self {
        case .vote: return "Start the vote"
        case .spin: return "Start the spin"
        case .surprise: return "Start the wheel"
        case .plan: return "Send the plan"
        }
    }
}

/// One way to decide, as a row: icon, name, what it means, and a check.
struct SetupModeRow: View {
    let option: SetupMode
    let isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: option.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isOn ? Theme.onSaffron : Theme.accentText)
                .frame(width: 36, height: 36)
                .background(isOn ? Theme.saffron : Theme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(Theme.body(16, .semibold))
                    .foregroundStyle(Theme.text)
                Text(option.line)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isOn ? Theme.saffron : Theme.muted.opacity(0.4))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Optional for Vote, Spin, and Surprise us: when you're eating, so
/// friends can plan around it (Saturday, not just "tonight").
struct PlanWhenSection: View {
    @Binding var hasTime: Bool
    @Binding var meetTime: Date

    var body: some View {
        Section {
            Toggle("Set a date & time", isOn: $hasTime.animation())
                .tint(Theme.saffron)
            if hasTime {
                DatePicker("Date & time", selection: $meetTime, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
            }
        } header: {
            Text("When")
        } footer: {
            Text(hasTime
                 ? "Everyone sees it now. Once it’s decided, phones with the app get a leave-by reminder."
                 : "Skip it to set the time after you decide.")
        }
        .listRowBackground(Theme.surface)
    }
}
