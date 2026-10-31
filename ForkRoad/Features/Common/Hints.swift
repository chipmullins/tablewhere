import SwiftUI

/// One-time tips, shown right where each feature lives. Each one shows until
/// you close it or use the feature it points at. Settings → "Show tips again"
/// brings them all back.
enum Hint: String, CaseIterable {
    /// Right after onboarding: points at the Spin button.
    case spinFirst
    case discoverMap
    case myWheel
    case listsAdd
    case groupStart

    var icon: String {
        switch self {
        case .spinFirst: return "sparkles"
        case .discoverMap: return "hand.tap.fill"
        case .myWheel: return "circle.dashed"
        case .listsAdd: return "plus.circle.fill"
        case .groupStart: return "person.3.fill"
        }
    }

    var title: String {
        switch self {
        case .spinFirst: return "Tap Spin and let it pick"
        case .discoverMap: return "Look somewhere else"
        case .myWheel: return "Make a custom spin"
        case .listsAdd: return "Add any place"
        case .groupStart: return "Pick with friends"
        }
    }

    var text: String {
        switch self {
        case .spinFirst:
            return "It picks from places near you, and skips ones you landed on this week when it can."
        case .discoverMap:
            return "Open the map and tap anywhere to search there, like the other side of town."
        case .myWheel:
            return "Choose Custom to spin just the places you pick, even ones that aren’t on a list."
        case .listsAdd:
            return "Tap + to search for a restaurant, or add one that isn’t on Apple Maps with your own notes."
        case .groupStart:
            return "Vote or spin with friends. They join from iMessage or a web link, no app needed."
        }
    }

    /// Hints that only show when something asks for them (not on their own).
    var waitsToBeShown: Bool { self == .spinFirst }

    /// A hint that should wait until another one is done.
    var after: Hint? { self == .myWheel ? .spinFirst : nil }

    @MainActor var isVisible: Bool { HintStore.shared.isVisible(self) }
    @MainActor func show() { HintStore.shared.show(self) }
    @MainActor func dismiss() { HintStore.shared.dismiss(self) }
}

@MainActor @Observable
final class HintStore {
    static let shared = HintStore()

    private static let seenKey = "seenHints"
    private static let pendingKey = "pendingHints"

    private(set) var seen: Set<String>
    private(set) var pending: Set<String>

    private init() {
        let defaults = UserDefaults.standard
        seen = Set(defaults.stringArray(forKey: Self.seenKey) ?? [])
        pending = Set(defaults.stringArray(forKey: Self.pendingKey) ?? [])
    }

    func isVisible(_ hint: Hint) -> Bool {
        guard !seen.contains(hint.rawValue) else { return false }
        if hint.waitsToBeShown && !pending.contains(hint.rawValue) { return false }
        if let before = hint.after, isVisible(before) { return false }
        return true
    }

    func show(_ hint: Hint) {
        seen.remove(hint.rawValue)
        pending.insert(hint.rawValue)
        save()
    }

    func dismiss(_ hint: Hint) {
        guard !seen.contains(hint.rawValue) || pending.contains(hint.rawValue) else { return }
        seen.insert(hint.rawValue)
        pending.remove(hint.rawValue)
        save()
    }

    /// Settings → Show tips again.
    func reset() {
        seen = []
        pending = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(Array(seen), forKey: Self.seenKey)
        UserDefaults.standard.set(Array(pending), forKey: Self.pendingKey)
    }
}

/// The card a hint shows as. Renders nothing once the hint is done.
struct HintCard: View {
    let hint: Hint
    @State private var store = HintStore.shared

    init(_ hint: Hint) { self.hint = hint }

    var body: some View {
        if store.isVisible(hint) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: hint.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 36, height: 36)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(hint.title)
                        .font(Theme.body(15, .bold))
                        .foregroundStyle(Theme.text)
                    Text(hint.text)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { hint.dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tip")
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.saffron.opacity(0.45)))
            .accessibilityElement(children: .contain)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
