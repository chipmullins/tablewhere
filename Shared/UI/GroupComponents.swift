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
    let isLeading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    MonogramTile(name: option.name, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(option.name)
                                .font(Theme.body(16, .semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            if isLeading {
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
                    Text("\(votes)")
                        .font(Theme.display(22))
                        .foregroundStyle(isLeading ? Theme.saffron : Theme.text)
                        .contentTransition(.numericText())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x23232E))
                        Capsule()
                            .fill(isLeading ? Theme.saffron : Color(hex: 0x5C5A66))
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 8)
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
