import SwiftUI
import PickerCore

/// Asks for the name friends will see. Shared by the app and the iMessage extension.
struct NamePromptView: View {
    var onDone: (String) -> Void
    @State private var name = Identity.displayName ?? ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What should friends call you?")
                .font(Theme.display(22))
                .foregroundStyle(Theme.text)
            TextField("Your first name", text: $name)
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($focused)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(Theme.text)
                .onSubmit(save)
            Button(action: save) {
                Text("Continue")
                    .font(Theme.display(17))
                    .foregroundStyle(Theme.onSaffron)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(trimmed.isEmpty)
            .opacity(trimmed.isEmpty ? 0.5 : 1)
        }
        .padding(20)
        .onAppear { focused = true }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    private func save() {
        guard !trimmed.isEmpty else { return }
        Identity.displayName = trimmed
        onDone(trimmed)
    }
}

/// One option in a live vote, with its bar and voters.
struct VoteOptionRow: View {
    let option: GroupOption
    let votes: Int
    let totalSlots: Int
    let voters: [String]
    let isMine: Bool
    /// False in spin mode, where nobody votes: hides the count and bar.
    let isLeading: Bool
    let isEnabled: Bool
    var showsVotes: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    MonogramTile(name: option.name, category: option.category, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(option.name)
                                .font(Theme.body(16, .semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            if isMine && showsVotes {
                                Text("YOUR VOTE")
                                    .font(Theme.body(10, .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(Theme.accentText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 5))
                            } else if isLeading {
                                Text("LEADING")
                                    .font(Theme.body(10, .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(Theme.onSaffron)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                        Text(voters.isEmpty ? "\(option.category) · added by \(option.addedBy)" : voters.joined(separator: ", "))
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if showsVotes {
                        Text("\(votes)")
                            .font(Theme.display(22))
                            .foregroundStyle(isLeading ? Theme.accentText : Theme.text)
                            .contentTransition(.numericText())
                    }
                }
                if showsVotes { GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule()
                            .fill(isLeading ? Theme.saffron : Theme.trackFill)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 8) }
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isMine ? Theme.saffron : Theme.hairline, lineWidth: isMine ? 1.5 : 1)
            )
            .animation(.snappy, value: votes)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("\(option.name), \(votes) votes\(isMine ? ", your vote" : "")")
    }

    private var fraction: CGFloat {
        guard totalSlots > 0 else { return 0 }
        return min(1, CGFloat(votes) / CGFloat(totalSlots))
    }
}

/// The big saffron "the group picked…" card.
struct WinnerCard: View {
    let option: GroupOption
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THE GROUP PICKED")
                .font(Theme.body(12, .heavy))
                .tracking(1.2)
            Text(option.name)
                .font(Theme.display(32))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(Theme.body(14, .semibold))
        }
        .foregroundStyle(Theme.onSaffron)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// After a vote closes: every place, who voted for it, and who didn't vote.
/// Shared by the app and the iMessage extension (the web page has its own copy).
struct VoteBreakdown: View {
    let options: [GroupOption]
    let tally: Tally
    let winnerID: String?
    /// Members who never voted.
    var nonVoters: [String] = []

    /// Winner first, then most votes, then the original order.
    private var ordered: [GroupOption] {
        let position = Dictionary(uniqueKeysWithValues: options.enumerated().map { ($1.id, $0) })
        return options.sorted { a, b in
            if (a.id == winnerID) != (b.id == winnerID) { return a.id == winnerID }
            let ca = tally.count(for: a.id), cb = tally.count(for: b.id)
            if ca != cb { return ca > cb }
            return (position[a.id] ?? 0) < (position[b.id] ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "How everyone voted")
            VStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, option in
                    if index > 0 { Divider().overlay(Theme.hairline) }
                    row(option)
                }
                if !nonVoters.isEmpty {
                    Divider().overlay(Theme.hairline)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "moon.zzz")
                            .foregroundStyle(Theme.muted)
                        Text("Didn’t vote: \(nonVoters.joined(separator: ", "))")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline))
        }
    }

    private func row(_ option: GroupOption) -> some View {
        let count = tally.count(for: option.id)
        let voters = tally.votersByOption[option.id] ?? []
        let isWinner = option.id == winnerID
        return HStack(spacing: 12) {
            MonogramTile(name: option.name, category: option.category, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(option.name)
                        .font(Theme.body(15, .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if isWinner {
                        Image(systemName: "crown.fill")
                            .font(Theme.body(11, .bold))
                            .foregroundStyle(Theme.accentText)
                            .accessibilityLabel("Winner")
                    }
                }
                Text(voters.isEmpty ? "No votes" : voters.joined(separator: ", "))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("\(count)")
                .font(Theme.display(20))
                .foregroundStyle(isWinner ? Theme.accentText : Theme.text)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(option.name), \(count) vote\(count == 1 ? "" : "s")\(voters.isEmpty ? "" : ": " + voters.joined(separator: ", "))")
    }
}

/// The creator's note shown with the plan ("Bring a gift!").
struct PlanNoteCard: View {
    let note: String
    let author: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.bubble.fill")
                .font(Theme.body(16, .semibold))
                .foregroundStyle(Theme.accentText)
            VStack(alignment: .leading, spacing: 3) {
                Text(note)
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("— \(author)")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Note from \(author): \(note)")
    }
}
