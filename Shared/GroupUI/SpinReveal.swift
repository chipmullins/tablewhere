import SwiftUI
import PickerCore

/// The wheel landing on the winner, shown to everyone watching a Group Spin
/// when it's spun (in the app and the iMessage app). Tap to skip.
struct SpinReveal: View {
    let names: [String]
    let winner: String
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @State private var shown = ""
    @State private var landed = false

    var body: some View {
        ZStack {
            Theme.night.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: landed ? "party.popper.fill" : "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.saffron)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(landed ? "THE WHEEL PICKED" : "SPINNING…")
                    .font(Theme.body(12, .heavy))
                    .tracking(1.4)
                    .foregroundStyle(Theme.accentText)
                Text(shown)
                    .font(Theme.display(landed ? 36 : 30))
                    .foregroundStyle(landed ? Theme.text : Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 24)
                    .id(shown)
                    .transition(reduceMotion ? .opacity : .push(from: .bottom))
            }
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .sensoryFeedback(.selection, trigger: shown)
        .sensoryFeedback(.success, trigger: landed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(landed ? "The wheel picked \(winner)" : "Spinning")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to close")
        .accessibilityAction { onDone() }
        .task { await run() }
    }

    private func run() async {
        let pool = names.isEmpty ? [winner] : names
        if !reduceMotion && pool.count > 1 {
            var delay = 0.06
            var index = Int.random(in: 0..<pool.count)
            for _ in 0..<20 {
                index = (index + 1) % pool.count
                withAnimation(.snappy(duration: min(delay, 0.25))) { shown = pool[index] }
                try? await Task.sleep(for: .seconds(delay))
                delay *= 1.17
            }
        }
        withAnimation(.bouncy) {
            shown = winner
            landed = true
        }
        let announcement: String = "The wheel picked \(winner)"
        AccessibilityNotification.Announcement(announcement).post()
        // Give VoiceOver time to finish the announcement before closing.
        try? await Task.sleep(for: .seconds(voiceOverOn ? 3.5 : 1.8))
        // Tapped to skip already (the view went away): don't finish twice.
        guard !Task.isCancelled else { return }
        onDone()
    }
}
