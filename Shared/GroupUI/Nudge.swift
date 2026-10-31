import SwiftUI
import PickerCore

/// "Still waiting on Amy and Ben…" for the creator to drop into the chat.
enum Nudge {
    /// Who hasn't done their part yet: in a spin, added a pick; in an open
    /// vote, voted. The creator is left out. Empty when nobody's waiting.
    static func waiting(session: GroupSession, members: [GroupMember], votes: [GroupVote]) -> [GroupMember] {
        guard session.status == .open else { return [] }
        let others = members.filter { !session.isOwned(by: $0.id) }
        switch session.mode {
        case .spin:
            return session.waitingOnPicks(members: others)
        case .vote:
            let voted = Set(votes.map(\.voterID))
            return others.filter { !voted.contains($0.id) }
        }
    }

    /// The message, or nil if there's nobody to nudge.
    static func text(session: GroupSession, members: [GroupMember], votes: [GroupVote]) -> String? {
        let names = waiting(session: session, members: members, votes: votes).map(\.name)
        guard !names.isEmpty else { return nil }
        let who: String
        switch names.count {
        case 1: who = names[0]
        case 2: who = "\(names[0]) and \(names[1])"
        default: who = names.dropLast().joined(separator: ", ") + ", and " + names.last!
        }
        let doing = session.mode == .spin ? "to add your pick to the wheel" : "for your vote"
        var text = "Still waiting on \(who) \(doing) for “\(session.title)”! 🍽️"
        if let url = GroupLinks.webURL(sessionID: session.id, host: AppConfig.webHost) {
            text += "\n\(url.absoluteString)"
        }
        return text
    }
}

/// The creator's tools while a group is open: nudge whoever's holding things
/// up, and remove a place. Used by the app and the iMessage app.
struct OwnerGroupTools: View {
    let session: GroupSession
    /// The nudge message, or nil when nobody's waiting.
    let nudge: String?
    /// The app shares the nudge; iMessage drops it into the chat.
    var sendNudge: ((String) -> Void)? = nil
    let onRemove: (GroupOption) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let nudge {
                if let sendNudge {
                    Button { sendNudge(nudge) } label: { nudgeLabel }
                        .buttonStyle(.plain)
                } else {
                    ShareLink(item: nudge) { nudgeLabel }
                }
            }
            if session.options.count > 1 {
                Menu {
                    Section("Remove a place") {
                        ForEach(session.options) { option in
                            Button(option.name, role: .destructive) { onRemove(option) }
                        }
                    }
                } label: {
                    toolLabel("Remove", systemImage: "minus.circle")
                }
            }
        }
    }

    private var nudgeLabel: some View {
        toolLabel("Nudge everyone", systemImage: "hand.wave")
    }

    private func toolLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(Theme.body(14, .semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
