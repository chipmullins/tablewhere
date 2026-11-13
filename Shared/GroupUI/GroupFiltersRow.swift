import SwiftUI
import PickerCore

/// "Group filters" (Vote and Spin our picks): the organizer turns on No fast
/// food and/or No coffee & sweets for everyone's picks. Off by default. One
/// row with a menu, used on setup (app and iMessage) and in the lobby.
struct GroupFiltersRow: View {
    @Binding var filters: GroupFilters
    var isEnabled = true

    var body: some View {
        Menu {
            Toggle(isOn: $filters.noFastFood) { Label("No fast food", systemImage: "takeoutbag.and.cup.and.straw") }
            Toggle(isOn: $filters.noCoffeeSweets) { Label("No coffee & sweets", systemImage: "cup.and.saucer") }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(Theme.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Group filters")
                        .font(Theme.body(15, .semibold))
                        .foregroundStyle(Theme.text)
                    Text("For everyone’s picks")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(Self.valueLabel(filters))
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(filters.isActive ? Theme.accentText : Theme.muted)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(Theme.body(11, .bold))
                    .foregroundStyle(Theme.muted)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .sensoryFeedback(Haptic.tick, trigger: filters)
        .accessibilityLabel("Group filters")
        .accessibilityValue(Self.valueLabel(filters))
    }

    static func valueLabel(_ filters: GroupFilters) -> String {
        switch (filters.noFastFood, filters.noCoffeeSweets) {
        case (true, true): return "No fast food, coffee"
        case (true, false): return "No fast food"
        case (false, true): return "No coffee & sweets"
        default: return "Off"
        }
    }
}

/// "No fast food in this group" under a plan's title, for everyone.
struct GroupFiltersLine: View {
    let session: GroupSession

    var body: some View {
        if session.acceptsChanges, !session.isSurprise, session.mode != .plan,
           let text = session.groupFilters?.summary {
            Label(text, systemImage: "line.3.horizontal.decrease.circle")
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.accentText)
        }
    }
}

/// The organizer's group filters in the lobby while the plan is open: saved
/// to the plan as soon as they change.
struct GroupFiltersCard: View {
    let session: GroupSession
    @State private var draft: GroupFilters?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupFiltersRow(filters: Binding(
                get: { draft ?? session.groupFilters ?? GroupFilters() },
                set: { save($0) }
            ))
            if failed {
                Text("Couldn’t save that. Check your connection and try again.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .card()
        .onChange(of: session.groupFilters) { draft = nil }
    }

    private func save(_ filters: GroupFilters) {
        draft = filters
        failed = false
        Task {
            do {
                try await GroupService.shared.setGroupFilters(sessionID: session.id, filters: filters)
            } catch {
                draft = nil
                failed = true
            }
        }
    }
}
