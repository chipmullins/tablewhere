import SwiftUI

/// The sleek tab bar (1.2): a dark pill floating over the content. Only the
/// active tab shows its name, on a saffron capsule; the others are icons with
/// VoiceOver labels. The system tab bar is hidden (see RootTabView).
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var capsule
    @Environment(\.dynamicTypeSize) private var typeSize

    private let tabs: [(tab: AppTab, title: String, icon: String, activeIcon: String)] = [
        (.discover, "Discover", "safari", "safari.fill"),
        (.spin, "Spin", "sparkles", "sparkles"),
        (.lists, "Lists", "heart", "heart.fill"),
        (.group, "Group", "person.2", "person.2.fill"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs.indices, id: \.self) { index in
                let item = tabs[index]
                let isOn = selection == item.tab
                Button {
                    if selection != item.tab {
                        withAnimation(.snappy(duration: 0.28)) { selection = item.tab }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isOn ? item.activeIcon : item.icon)
                            .font(.system(size: 18, weight: .semibold))
                        if isOn {
                            Text(item.title)
                                .font(Theme.body(14, .bold))
                                .lineLimit(1)
                                .fixedSize()
                                .transition(.opacity)
                        }
                    }
                    .foregroundStyle(isOn ? Theme.onSaffron : Theme.onInk)
                    .padding(.horizontal, isOn ? 18 : 0)
                    .frame(minWidth: 48, minHeight: 48)
                    .background {
                        if isOn {
                            Capsule().fill(Theme.saffron)
                                .matchedGeometryEffect(id: "active", in: capsule)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
                .accessibilityHint(isOn ? "" : "Opens \(item.title)")
            }
        }
        .padding(6)
        .background(Theme.ink, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
        .shadow(color: .black.opacity(0.25), radius: 17, y: 14)
        .sensoryFeedback(Haptic.tick, trigger: selection)
        // Fixed size like the system tab bar: very large text would push it off screen.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }
}

extension View {
    /// Keeps a tab's content (and everything pushed on it) clear of the floating tab bar.
    func floatingTabBarClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: Theme.tabBarClearance).allowsHitTesting(false)
        }
    }
}
