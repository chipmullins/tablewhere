import SwiftUI
import PickerCore

/// Wording shared by the app's group screen and the iMessage app, so both
/// say the same thing.
enum GroupWording {
    /// "Waiting on Sam, Alex", "Everyone has voted", "Locked in by Chip".
    static func line(_ session: GroupSession, nonVoterNames: [String]) -> String {
        if session.status == .decided {
            switch session.mode {
            case .vote: return "Locked in by \(session.createdByName)"
            case .spin: return "Spun by \(session.createdByName)"
            case .plan: return "Planned by \(session.createdByName)"
            }
        }
        switch session.mode {
        case .vote:
            if nonVoterNames.isEmpty { return "Everyone has voted" }
            return "Waiting on " + list(nonVoterNames)
        case .spin:
            // Who's still picking shows just below (SpinProgressLine).
            let count = session.options.count
            if session.isSurprise { return "\(count) places nearby on the wheel" }
            return "\(count) place\(count == 1 ? "" : "s") in the wheel"
        case .plan:
            return "Planned by \(session.createdByName)"
        }
    }

    /// Who decides, for everyone who isn't the creator.
    static func whoDecides(_ session: GroupSession) -> String {
        switch session.mode {
        case .vote: return "\(session.createdByName) will lock in the result"
        case .spin:
            return session.isSurprise
                ? "\(session.createdByName) will spin, and the wheel picks one of these"
                : "\(session.createdByName) will spin when everyone’s ready"
        case .plan: return "\(session.createdByName) picked the place"
        }
    }

    /// The message that goes with an invite link.
    static func inviteText(_ session: GroupSession) -> String {
        let code = JoinCode.display(session.joinCode)
        switch session.mode {
        case .vote:
            return "Help pick where we eat! Vote here, or join in Tablewhere with code \(code)."
        case .spin where session.isSurprise:
            return "Letting the wheel pick where we eat! Watch here, or join in Tablewhere with code \(code)."
        case .spin:
            return "Add your pick for the group spin! Add it here, or join in Tablewhere with code \(code)."
        case .plan:
            return session.hasRSVP
                ? "Here’s the plan! Let me know if you’re in here, or in Tablewhere with code \(code)."
                : "Here’s the plan! Details and directions here, or in Tablewhere with code \(code)."
        }
    }

    /// Locking in with nobody voting, or spinning one place, is probably a slip.
    /// Nil when it's fine to go ahead.
    static func lockInWarning(_ session: GroupSession, totalVotes: Int) -> (title: String, message: String)? {
        let first = session.options.first?.name ?? "it"
        if session.mode == .spin {
            guard session.options.count <= 1 else { return nil }
            return ("Only one place on the wheel", "The spin will land on \(first). Wait for friends to add theirs?")
        }
        if session.options.count <= 1 {
            return ("Only one place to pick", "It’ll be \(first).")
        }
        guard totalVotes == 0 else { return nil }
        return ("Nobody has voted yet", "The app will pick at random from all \(session.options.count) places.")
    }

    private static func list(_ names: [String]) -> String {
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? "\(shown) + \(names.count - 3) more" : shown
    }
}

/// "Closes in 4:59", ticking every second.
struct VoteCountdown: View {
    let closesAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(closesAt.timeIntervalSince(context.date)))
            Label(remaining > 0 ? "Closes in \(remaining / 60):\(String(format: "%02d", remaining % 60))" : "Voting closed",
                  systemImage: "timer")
                .font(Theme.body(13, .bold))
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(Theme.accentSoft, in: Capsule())
                .monospacedDigit()
        }
    }
}
