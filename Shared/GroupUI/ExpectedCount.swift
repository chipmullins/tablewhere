import SwiftUI
import PickerCore

/// "How many are eating, counting you?" for the creator of a vote or spin,
/// so everyone sees "3 of 6 picks in" and "Everyone's in" waits for people
/// who haven't opened the link yet. Optional: Skip keeps counting joins.
/// iMessage plans fill it in from the chat, so this shows "Expecting 5 · Edit".
struct ExpectedCountCard: View {
    let session: GroupSession
    let joined: Int

    @State private var editing = false
    @State private var value: Int
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var skipped: Bool
    @State private var stepTaps = 0

    init(session: GroupSession, joined: Int) {
        self.session = session
        self.joined = joined
        // Read up front, so a skipped plan doesn't flash the prompt.
        _skipped = State(initialValue: UserDefaults.standard.bool(forKey: "expectedSkipped.\(session.id)"))
        _value = State(initialValue: Self.start(session, joined: joined))
    }

    private static func start(_ session: GroupSession, joined: Int) -> Int {
        let range = GroupSession.expectedCountRange
        let lowest = max(range.lowerBound, min(joined, range.upperBound))
        return min(max(session.expectedCount ?? max(joined, 4), lowest), range.upperBound)
    }

    private var skipKey: String { "expectedSkipped.\(session.id)" }
    private var range: ClosedRange<Int> { GroupSession.expectedCountRange }
    /// Can't expect fewer people than have already joined.
    private var lowest: Int { max(range.lowerBound, min(joined, range.upperBound)) }

    var body: some View {
        Group {
            if editing || (session.expectedCount == nil && !skipped) {
                prompt
            } else if let expected = session.headcount(joined: joined) {
                summary("Expecting \(expected) · counting you", action: "Edit")
            } else {
                summary("Know how many are eating?", action: "Set it")
            }
        }
        .sensoryFeedback(Haptic.tick, trigger: stepTaps)
    }

    private var startingValue: Int { Self.start(session, joined: joined) }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How many are eating, counting you?")
                .font(Theme.body(15, .semibold))
                .foregroundStyle(Theme.text)
            Text(session.mode == .spin
                 ? "Everyone sees “2 of \(value) picks in,” and you hear when they’re all in."
                 : "Everyone sees “2 of \(value) voted,” and you hear when they all have.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                stepButton("minus", label: "One fewer", disabled: value <= lowest) { value -= 1 }
                Text("\(value) people")
                    .font(Theme.display(18))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
                    .frame(minWidth: 96)
                    .accessibilityHidden(true)
                stepButton("plus", label: "One more", disabled: value >= range.upperBound) { value += 1 }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityValue("\(value) people")
            if let errorMessage {
                Text(errorMessage).font(Theme.body(12)).foregroundStyle(Theme.danger)
            }
            HStack(spacing: 10) {
                Button(session.expectedCount == nil ? "Skip" : "Not sure") { clear() }
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .buttonStyle(.pressable)
                Button("Set") { save(value) }
                    .font(Theme.body(14, .bold))
                    .foregroundStyle(Theme.onSaffron)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .buttonStyle(.pressable)
            }
            .disabled(saving)
        }
        .padding(14)
        .card()
    }

    private func summary(_ text: String, action: String) -> some View {
        HStack(spacing: 10) {
            Label(text, systemImage: "person.2.fill")
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Button(action) {
                value = startingValue
                editing = true
            }
            .font(Theme.body(13, .bold))
            .foregroundStyle(Theme.accentText)
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 4)
    }

    private func stepButton(_ symbol: String, label: String, disabled: Bool, _ change: @escaping () -> Void) -> some View {
        Button {
            change()
            stepTaps += 1
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 40)
                .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private func save(_ count: Int?) {
        saving = true
        errorMessage = nil
        Task {
            defer { saving = false }
            do {
                try await GroupService.shared.setExpectedCount(sessionID: session.id, count: count)
                editing = false
            } catch {
                // Keep the prompt up so the error shows.
                errorMessage = GroupService.message(for: error)
                editing = true
            }
        }
    }

    /// Skip (never set): hide the prompt for this plan. Not sure (was set): clear it.
    private func clear() {
        UserDefaults.standard.set(true, forKey: skipKey)
        skipped = true
        if session.expectedCount != nil {
            editing = true  // stays up until it's cleared (or shows why not)
            save(nil)
        } else {
            editing = false
        }
    }
}
