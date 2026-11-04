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
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            TextField("Your first name", text: $name)
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 50)
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

    /// 30 characters at most, same as the web page.
    private var trimmed: String { String(name.trimmingCharacters(in: .whitespaces).prefix(30)) }

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
    /// False in spin mode, where nobody votes: hides the count and bar.
    var showsVotes: Bool = true
    /// Someone in the group blacklisted it: shown, but it can't win.
    var isRuledOut: Bool = false
    let action: () -> Void

    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    MonogramTile(name: option.name, category: option.category, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(option.name)
                                .font(Theme.body(16, .semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            if isRuledOut {
                                Text("RULED OUT")
                                    .font(Theme.body(10, .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Theme.track, in: RoundedRectangle(cornerRadius: 5))
                            }
                            if isMine && showsVotes {
                                Text("YOUR VOTE")
                                    .font(Theme.body(10, .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(Theme.accentText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 5))
                            } else if isLeading && showsVotes && !isRuledOut {
                                Text("LEADING")
                                    .font(Theme.body(10, .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(Theme.onSaffron)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                        Text(isRuledOut ? "Someone in the group blacklisted it, so it can’t win"
                             : voters.isEmpty ? "\(option.category) · added by \(option.addedBy)" : shortVoterList(voters))
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
            .opacity(isRuledOut ? 0.6 : 1)
            .animation(.snappy, value: votes)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityText)
        .sensoryFeedback(Haptic.tick, trigger: taps)
    }

    /// Vote: "Tacos, 2 votes, leading, your vote, voted by Amy, Ben".
    /// Spin: "Tacos, Mexican, added by Amy" (no vote talk).
    private var accessibilityText: String {
        var parts = [option.name]
        if showsVotes {
            parts.append("\(votes) vote\(votes == 1 ? "" : "s")")
            if isLeading && !isRuledOut { parts.append("leading") }
            if isMine { parts.append("your vote") }
        }
        if isRuledOut {
            parts.append("ruled out, someone in the group blacklisted it")
        } else if showsVotes && !voters.isEmpty {
            parts.append("voted by \(voters.joined(separator: ", "))")
        } else {
            parts.append("\(option.category), added by \(option.addedBy)")
        }
        return parts.joined(separator: ", ")
    }

    private var fraction: CGFloat {
        guard totalSlots > 0 else { return 0 }
        return min(1, CGFloat(votes) / CGFloat(totalSlots))
    }
}

/// Stand-in for a group plan while it first loads: the header (or, `compact`
/// for iMessage, a title line), then three option rows. One "Loading" for VoiceOver.
struct GroupPlanSkeleton: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBar(width: 170, height: 18)
                    SkeletonBar(width: 230, height: 10)
                }
                .shimmering()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonBar(width: 70, height: 10)
                        SkeletonBar(width: 210, height: 28)
                    }
                    .shimmering()
                    HStack(spacing: 12) {
                        Circle().fill(Theme.surfaceHigh).frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 7) {
                            SkeletonBar(width: 110, height: 12)
                            SkeletonBar(width: 170, height: 10)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .card()
                    .shimmering()
                }
                .padding(.top, 8)
            }
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in optionRow }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .loadingSkeleton()
    }

    /// Shaped like `VoteOptionRow`: tile, name and detail, and the vote bar.
    private var optionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surfaceHigh)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBar(width: 150, height: 12)
                    SkeletonBar(width: 100, height: 9)
                }
                Spacer(minLength: 0)
            }
            Capsule().fill(Theme.track).frame(height: 8)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline))
        .shimmering()
    }
}

/// The big saffron "the group picked…" card.
struct WinnerCard: View {
    let option: GroupOption
    let detail: String
    /// "THE PLAN" for an "I'll pick" plan.
    var eyebrow = "THE GROUP PICKED"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(eyebrow.capitalized): \(option.name). \(detail)")
        .accessibilityAddTraits(.isHeader)
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
        // uniquingKeysWith: the same place can land in a vote twice if two
        // people add it at once, and uniqueKeysWithValues would crash on that.
        let position = Dictionary(options.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
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
                            .accessibilityHidden(true)
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
        .accessibilityLabel("\(option.name)\(isWinner ? ", winner" : ""), \(count) vote\(count == 1 ? "" : "s")\(voters.isEmpty ? "" : ": " + voters.joined(separator: ", "))")
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
                .accessibilityHidden(true)
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

/// "Add your pick" / "Suggest a place", following the group's limits: one
/// place each in a spin (creator too); in a vote, the creator can add up to
/// 12 and everyone else can suggest one. Once your pick is in, it shows it,
/// with Change to swap it for another place.
struct AddPlaceButton: View {
    let session: GroupSession
    let userID: String?
    let action: () -> Void

    var body: some View {
        if let userID, let mine = session.pick(of: userID), !(session.mode == .vote && session.isOwned(by: userID)) {
            HStack(spacing: 10) {
                Label("Your pick: \(mine.name)", systemImage: "checkmark.circle.fill")
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if session.status == .open {
                    Button("Change", action: action)
                        .font(Theme.body(14, .bold))
                        .foregroundStyle(Theme.accentText)
                        .accessibilityLabel("Change your pick")
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            let full = session.options.count >= GroupSession.maxOptions
            Button(action: action) {
                Label(full ? "Full (12 places)" : title, systemImage: "plus.circle.fill")
                    .font(Theme.body(15, .bold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.saffron.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .disabled(full || userID.map { !session.canAdd(userID: $0) } ?? false)
        }
    }

    private var title: String {
        switch session.mode {
        case .spin: return "Add your pick to the wheel"
        case .plan: return "Change the place"
        case .vote:
            if let userID, session.isOwned(by: userID) { return "Add another place" }
            return "Suggest a place (one each)"
        }
    }
}

/// "Waiting on picks from Amy, Ben" / "Everyone’s in", for a spin.
struct SpinProgressLine: View {
    let waiting: [GroupMember]
    let memberCount: Int

    var body: some View {
        Label(text, systemImage: waiting.isEmpty ? "checkmark.circle.fill" : "hourglass")
            .font(Theme.body(13, .semibold))
            .foregroundStyle(waiting.isEmpty ? Theme.accentText : Theme.muted)
    }

    private var text: String {
        if waiting.isEmpty { return memberCount > 1 ? "Everyone’s pick is in. Ready to spin!" : "Your pick is in. Invite friends to add theirs." }
        let names = waiting.map(\.name)
        let list = names.count <= 3 ? names.joined(separator: ", ") : "\(names.prefix(3).joined(separator: ", ")) + \(names.count - 3) more"
        return "Waiting on picks from \(list)"
    }
}

/// Notes under a vote's heading: time's up, everything ruled out, or your
/// vote being on a place that can't win.
struct VoteNotices: View {
    let session: GroupSession
    let isOwner: Bool
    let everythingRuledOut: Bool
    let myVoteIsRuledOut: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.isTimeUp {
                notice(isOwner ? "Time’s up! Lock it in to see what won." : "Time’s up! \(session.createdByName) will lock it in.",
                       systemImage: "timer")
            }
            if everythingRuledOut {
                notice("Someone has every place here blacklisted, so they’re all back in.", systemImage: "arrow.uturn.backward")
            }
            if myVoteIsRuledOut && session.acceptsChanges {
                notice("Your vote is on a place someone ruled out, so it can’t win. Tap another place.",
                       systemImage: "exclamationmark.circle")
            }
        }
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(Theme.body(13, .semibold))
            .foregroundStyle(Theme.accentText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// "Sam, Alex, Jo + 8" so a big group's voters fit on one line.
func shortVoterList(_ names: [String], showing limit: Int = 3) -> String {
    guard names.count > limit + 1 else { return names.joined(separator: ", ") }
    return names.prefix(limit).joined(separator: ", ") + " + \(names.count - limit)"
}
