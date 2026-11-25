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
    /// Answers to an "I'll pick" plan.
    private(set) var rsvps: [GroupRSVP] = []
    /// "On my way" arrival times (1.1).
    private(set) var etas: [GroupETA] = []
    /// The first snapshot of `etas` has arrived (before it, empty means "not loaded").
    private(set) var etasLoaded = false
    private(set) var errorMessage: String?
    private(set) var isLoaded = false
    /// The group was ended (its document is gone), as opposed to a network hiccup.
    private(set) var isGone = false

    @ObservationIgnored nonisolated(unsafe) private var listeners: [ListenerRegistration] = []
    /// Signing in before listening: a second start (a double-tapped Try again) waits it out.
    @ObservationIgnored private var isStarting = false

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    deinit {
        listeners.forEach { $0.remove() }
    }

    var tally: Tally { Tally(options: session?.options ?? [], votes: votes) }

    /// Places someone in the group blacklisted (they can't win).
    var ruledOutIDs: Set<String> { session?.ruledOutIDs(members: members) ?? [] }

    /// Why a ruled-out place can't win, when it's the group's filters (nil:
    /// a blacklist, which never says whose).
    func ruledOutReason(_ optionID: String) -> String? {
        guard ruledOutIDs.contains(optionID), session?.filteredOutIDs.contains(optionID) == true else { return nil }
        return "Doesn’t fit the group’s filters"
    }

    /// Someone's blacklist covers every place, so they're all back in.
    var everythingRuledOut: Bool { session?.everythingRuledOut(members: members) ?? false }

    /// Everyone's scrambled blacklists, to hide those places when adding.
    var groupBlockedHashes: Set<String> { Set(members.flatMap { $0.blockedHashes ?? [] }) }

    /// In a spin, who hasn't added their pick yet.
    var waitingOnPicks: [GroupMember] { session?.waitingOnPicks(members: members) ?? [] }

    /// How many the plan is for, when known ("3 of 6 picks in"); nil: count joins.
    var headcount: Int? { session?.headcount(joined: members.count) }

    /// Expected people who haven't opened the link yet.
    var notJoinedYet: Int { session?.notJoinedYet(joined: members.count) ?? 0 }

    /// People whose pick is on the wheel.
    var picksIn: Int {
        guard let session else { return 0 }
        return members.filter { session.pick(of: $0.id) != nil }.count
    }

    /// People who have voted.
    var votedCount: Int { Set(votes.map(\.voterID)).count }

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

    /// "6 coming (4 + 2 guests)": the creator counts as coming unless they said no.
    var rsvpCount: RSVPCount {
        RSVPCount(rsvps, creatorID: session?.createdBy, creatorName: session?.createdByName)
    }

    /// People in the group (not the creator) who haven't answered the RSVP.
    var noRSVPYet: [String] {
        guard let session, session.hasRSVP else { return [] }
        let answered = Set(rsvps.map(\.userID))
        return members.filter { !session.isOwned(by: $0.id) && !answered.contains($0.id) }.map(\.name)
    }

    var myRSVP: GroupRSVP? {
        guard let uid = GroupService.shared.currentUserID else { return nil }
        return rsvps.first { $0.userID == uid }
    }

    var isOwner: Bool {
        guard let session, let uid = GroupService.shared.currentUserID else { return false }
        return session.isOwned(by: uid)
    }

    var myETA: GroupETA? {
        guard let uid = GroupService.shared.currentUserID else { return nil }
        return etas.first { $0.userID == uid }
    }

    /// Members minus anyone who said they can't make it (the On the way rows).
    var comingMembers: [GroupMember] {
        let declined = Set(rsvps.filter { !$0.going }.map(\.userID))
        return members.filter { !declined.contains($0.id) }
    }

    /// Who's expected at the table: everyone in the plan except people who
    /// said they can't make it (same rule as the server's "Everyone's here").
    var expectedAtTable: Int {
        let declined = Set(rsvps.filter { !$0.going }.map(\.userID))
        return members.filter { !declined.contains($0.id) }.count
    }

    /// "Sam ~7:05 · Alex ~7:12 · Jo hasn't left", or nil before anyone shares.
    var arrivalLine: String? {
        guard !etas.isEmpty else { return nil }
        // People who said they can't make it aren't "hasn't left".
        let declined = Set(rsvps.filter { !$0.going }.map(\.userID))
        return ArrivalBoard.line(etas: etas, members: members.filter { !declined.contains($0.id) },
                                 me: GroupService.shared.currentUserID) {
            $0.formatted(date: .omitted, time: .shortened)
        }
    }

    var myVote: String? {
        guard let uid = GroupService.shared.currentUserID else { return nil }
        return votes.first { $0.voterID == uid }?.optionID
    }

    /// Signs in if needed and starts listening.
    func start() async {
        guard listeners.isEmpty, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
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
                // It's there but this version can't read it (a newer kind of plan).
                self.errorMessage = !exists ? GroupError.sessionNotFound.localizedDescription
                    : decoded == nil ? "This plan needs a newer version of Tablewhere. Update the app to see it." : nil
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

        listeners.append(ref.collection("rsvps").addSnapshotListener { [weak self] snapshot, _ in
            let rsvps = snapshot?.documents.compactMap { try? $0.data(as: GroupRSVP.self) } ?? []
            Task { @MainActor in self?.rsvps = rsvps }
        })

        listeners.append(ref.collection("eta").addSnapshotListener { [weak self] snapshot, _ in
            let etas = snapshot?.documents.compactMap { try? $0.data(as: GroupETA.self) } ?? []
            Task { @MainActor in
                self?.etas = etas
                self?.etasLoaded = true
            }
        })

        listeners.append(ref.collection("members").addSnapshotListener { [weak self] snapshot, _ in
            let members = snapshot?.documents.compactMap { try? $0.data(as: GroupMember.self) } ?? []
            Task { @MainActor in self?.members = members }
        })
    }

    /// "Try again" after a failed start (no connection when it opened):
    /// listens from scratch. Firestore reconnects on its own once listening.
    func retry() async {
        stop()
        errorMessage = nil
        isLoaded = false
        await start()
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
}
