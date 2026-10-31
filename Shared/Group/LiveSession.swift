import Foundation
import Observation
import FirebaseFirestore
import PickerCore

/// A group session that stays up to date in real time.
/// Create one per screen; listeners stop when it's released.
@MainActor
@Observable
final class LiveSession {
    let sessionID: String

    private(set) var session: GroupSession?
    private(set) var votes: [GroupVote] = []
    private(set) var members: [GroupMember] = []
    private(set) var errorMessage: String?
    private(set) var isLoaded = false
    /// The group was ended (its document is gone), as opposed to a network hiccup.
    private(set) var isGone = false

    @ObservationIgnored nonisolated(unsafe) private var listeners: [ListenerRegistration] = []

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    deinit {
        listeners.forEach { $0.remove() }
    }

    var tally: Tally { Tally(options: session?.options ?? [], votes: votes) }

    /// Places someone in the group blacklisted (they can't win).
    var ruledOutIDs: Set<String> { session?.ruledOutIDs(members: members) ?? [] }

    /// Someone's blacklist covers every place, so they're all back in.
    var everythingRuledOut: Bool { session?.everythingRuledOut(members: members) ?? false }

    /// Everyone's scrambled blacklists, to hide those places when adding.
    var groupBlockedHashes: Set<String> { Set(members.flatMap { $0.blockedHashes ?? [] }) }

    /// In a spin, who hasn't added their pick yet.
    var waitingOnPicks: [GroupMember] { session?.waitingOnPicks(members: members) ?? [] }

    /// Names of members who haven't voted.
    var nonVoterNames: [String] {
        let voted = Set(votes.map(\.voterID))
        return members.filter { !voted.contains($0.id) }.map(\.name)
    }

    /// Same, for the status line: you show as "you".
    var waitingNames: [String] {
        let voted = Set(votes.map(\.voterID))
        let me = GroupService.shared.currentUserID
        return members.filter { !voted.contains($0.id) }.map { $0.id == me ? "you" : $0.name }
    }

    var isOwner: Bool {
        guard let session, let uid = GroupService.shared.currentUserID else { return false }
        return session.isOwned(by: uid)
    }

    var myVote: String? {
        guard let uid = GroupService.shared.currentUserID else { return nil }
        return votes.first { $0.voterID == uid }?.optionID
    }

    /// Signs in if needed and starts listening.
    func start() async {
        guard listeners.isEmpty else { return }
        do {
            _ = try await GroupService.shared.userID()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let ref = GroupService.shared.sessionRef(sessionID)

        listeners.append(ref.addSnapshotListener { [weak self] snapshot, error in
            let decoded = try? snapshot?.data(as: GroupSession.self)
            let exists = snapshot?.exists ?? false
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = GroupService.message(for: error)
                    self.isLoaded = true
                    return  // keep showing what we had; it's likely just the connection
                }
                self.errorMessage = exists ? nil : GroupError.sessionNotFound.localizedDescription
                self.isGone = !exists
                self.session = decoded
                self.isLoaded = true
                // No plan anymore (ended, reopened, or no time): drop this
                // phone's "time to leave" reminder, whoever made the change.
                if !exists || decoded?.status != .decided || decoded?.meetTime == nil {
                    LeaveBy.cancel(sessionID: self.sessionID)
                }
            }
        })

        listeners.append(ref.collection("votes").addSnapshotListener { [weak self] snapshot, _ in
            let votes = snapshot?.documents.compactMap { try? $0.data(as: GroupVote.self) } ?? []
            Task { @MainActor in self?.votes = votes }
        })

        listeners.append(ref.collection("members").addSnapshotListener { [weak self] snapshot, _ in
            let members = snapshot?.documents.compactMap { try? $0.data(as: GroupMember.self) } ?? []
            Task { @MainActor in self?.members = members }
        })
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
}
