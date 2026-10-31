import Foundation
import CryptoKit

// Group decisions (Phase 2). These types are plain Codable values with no
// Firebase dependency, so the app, the iMessage extension, and the tests can
// all use them. The app stores them in Firestore with the same field names.

/// How a group decides.
public enum GroupMode: String, Codable, Sendable, CaseIterable {
    /// Everyone votes; most votes wins, ties are broken fairly.
    case vote
    /// Everyone adds a place; the app picks one at random.
    case spin

    /// The name a group gets if you don't type one (app and iMessage alike).
    public var defaultTitle: String {
        self == .spin ? "Spin for dinner" : "Where should we eat?"
    }

    /// Most places you can start a vote with (you can add more later, up to
    /// `GroupSession.maxOptions`). A spin starts with your one pick.
    public static let maxStartingVoteOptions = 8
}

public enum GroupStatus: String, Codable, Sendable {
    case open
    case decided
}

/// A restaurant on the table in a group session.
public struct GroupOption: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var category: String
    public var latitude: Double
    public var longitude: Double
    public var address: String?
    public var phoneNumber: String?
    public var websiteURL: String?
    /// Display name of whoever added it.
    public var addedBy: String
    /// Firebase user ID of whoever added it. Nil on places from older versions.
    public var addedByID: String?

    public init(place: Place, addedBy: String, addedByID: String? = nil) {
        id = place.id
        name = place.name
        category = place.category
        latitude = place.latitude
        longitude = place.longitude
        address = place.address
        phoneNumber = place.phoneNumber
        websiteURL = place.websiteURL?.absoluteString
        self.addedBy = addedBy
        self.addedByID = addedByID
    }

    /// Converts back to a Place (distance unknown, so 0).
    public var place: Place {
        Place(id: id, name: name, category: category,
              latitude: latitude, longitude: longitude, distanceMeters: 0,
              phoneNumber: phoneNumber,
              websiteURL: websiteURL.flatMap(URL.init(string:)),
              address: address)
    }
}

/// One group decision: "Friday dinner".
public struct GroupSession: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    /// Six-character code friends type to join ("K7Q4MZ").
    public var joinCode: String
    /// Firebase user ID of whoever started it. Only they can lock in the result.
    public var createdBy: String
    public var createdByName: String
    public var createdAt: Date
    public var closesAt: Date?
    public var mode: GroupMode
    public var status: GroupStatus
    public var options: [GroupOption]
    public var winnerID: String?
    public var meetTime: Date?
    /// Who has used their one pick: user ID → option ID. In a spin, everyone
    /// (creator too) adds one place; in a vote, everyone but the creator can
    /// suggest one. Enforced by the Firestore rules. Nil on older sessions.
    public var picksBy: [String: String]?
    /// Short note from the creator sent with the plan ("Bring a gift!").
    /// Optional, so sessions from older app versions still decode.
    public var note: String?

    public init(id: String, title: String, joinCode: String, createdBy: String,
                createdByName: String, createdAt: Date = Date(), closesAt: Date? = nil,
                mode: GroupMode, status: GroupStatus = .open, options: [GroupOption],
                winnerID: String? = nil, meetTime: Date? = nil, picksBy: [String: String]? = nil,
                note: String? = nil) {
        self.id = id
        self.title = title
        self.joinCode = joinCode
        self.createdBy = createdBy
        self.createdByName = createdByName
        self.createdAt = createdAt
        self.closesAt = closesAt
        self.mode = mode
        self.status = status
        self.options = options
        self.winnerID = winnerID
        self.meetTime = meetTime
        self.picksBy = picksBy
        self.note = note
    }

    /// The note, trimmed, or nil when it's blank.
    public var trimmedNote: String? {
        let text = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// Longest note the creator can add.
    public static let maxNoteLength = 120

    public var winner: GroupOption? {
        guard let winnerID else { return nil }
        return options.first { $0.id == winnerID }
    }

    public func isOwned(by userID: String) -> Bool { createdBy == userID }

    /// The place this person added with their one pick, if any.
    public func pick(of userID: String) -> GroupOption? {
        if let id = picksBy?[userID], let option = options.first(where: { $0.id == id }) { return option }
        // Spin creators pick when they start the group.
        if mode == .spin { return options.first { $0.addedByID == userID } }
        return nil
    }

    /// Whether this person can still add a place: one pick each, except the
    /// creator of a vote, who can add up to the 12-place limit.
    /// A timed vote whose time is up (it stays "open" until someone locks it in).
    public var isTimeUp: Bool {
        guard status == .open, let closesAt else { return false }
        return closesAt.timeIntervalSinceNow <= 0
    }

    /// Votes and new places are accepted: open, and the timer (if any) hasn't run out.
    public var acceptsChanges: Bool { status == .open && !isTimeUp }

    public func canAdd(userID: String) -> Bool {
        guard acceptsChanges, options.count < GroupSession.maxOptions else { return false }
        if mode == .vote && isOwned(by: userID) { return true }
        return pick(of: userID) == nil
    }

    /// Most places a group can hold.
    public static let maxOptions = 12

    // MARK: Group blacklist

    /// Places someone in the group has blacklisted. They stay visible but
    /// can't win; nobody is told who blocked them.
    /// If every place is ruled out, nothing is (so the group isn't stuck);
    /// see `everythingRuledOut` to tell people why.
    public func ruledOutIDs(members: [GroupMember]) -> Set<String> {
        let blocked = blockedOptionIDs(members: members)
        return blocked.count == options.count ? [] : blocked
    }

    /// True when someone's blacklist covers every place in the group.
    public func everythingRuledOut(members: [GroupMember]) -> Bool {
        !options.isEmpty && blockedOptionIDs(members: members).count == options.count
    }

    private func blockedOptionIDs(members: [GroupMember]) -> Set<String> {
        let blocked = Set(members.flatMap { $0.blockedHashes ?? [] })
        guard !blocked.isEmpty else { return [] }
        return Set(options.map(\.id).filter { blocked.contains(GroupBlacklist.hash(placeID: $0, sessionID: id)) })
    }

    /// The vote leader among places that can still win (nil if tied or no votes).
    public func eligibleLeader(votes: [GroupVote], ruledOut: Set<String>) -> String? {
        Tally(options: eligibleOptions(ruledOut: ruledOut), votes: votes).leader
    }

    /// The places that can win: everything not ruled out (or everything, if
    /// the whole list is ruled out, so there's always an answer).
    public func eligibleOptions(ruledOut: Set<String>) -> [GroupOption] {
        let eligible = options.filter { !ruledOut.contains($0.id) }
        return eligible.isEmpty ? options : eligible
    }

    /// The winner: most votes (a random pick among tied places) or a random
    /// spin, skipping ruled-out places. A vote with no votes picks at random.
    /// Truly random, so spinning again after reopening can land somewhere new.
    public func pickWinner(votes: [GroupVote], ruledOut: Set<String> = []) -> String? {
        var generator = SystemRandomNumberGenerator()
        return pickWinner(votes: votes, ruledOut: ruledOut, using: &generator)
    }

    public func pickWinner<G: RandomNumberGenerator>(votes: [GroupVote], ruledOut: Set<String> = [],
                                                     using generator: inout G) -> String? {
        let eligible = eligibleOptions(ruledOut: ruledOut)
        switch mode {
        case .vote:
            let leaders = Tally(options: eligible, votes: votes).leaders
            if !leaders.isEmpty { return leaders.randomElement(using: &generator) }
            return eligible.randomElement(using: &generator)?.id
        case .spin:
            return eligible.randomElement(using: &generator)?.id
        }
    }

    // MARK: Spin progress

    /// In a spin, the members who haven't added their pick yet.
    public func waitingOnPicks(members: [GroupMember]) -> [GroupMember] {
        guard mode == .spin else { return [] }
        return members.filter { pick(of: $0.id) == nil }
    }
}

/// Shares blacklists with a group without listing them in the open: each
/// blacklisted place ID is hashed together with the session ID, so the same
/// place looks different in every group. It keeps lists from being read at a
/// glance; it isn't strong secrecy (someone could hash nearby places to guess).
/// Must match `blockedHash` in web/public/app.js.
public enum GroupBlacklist {
    public static func hash(placeID: String, sessionID: String) -> String {
        let digest = SHA256.hash(data: Data("\(sessionID)|\(placeID)".utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// A member's hashes for this group, capped so the document stays small.
    public static func hashes(placeIDs: [String], sessionID: String, limit: Int = 300) -> [String] {
        Array(placeIDs.prefix(limit)).map { hash(placeID: $0, sessionID: sessionID) }
    }
}

/// One person's vote. Stored one per person, so voting again replaces it.
public struct GroupVote: Codable, Hashable, Sendable {
    public var voterID: String
    public var voterName: String
    public var optionID: String
    public var votedAt: Date?

    public init(voterID: String, voterName: String, optionID: String, votedAt: Date? = nil) {
        self.voterID = voterID
        self.voterName = voterName
        self.optionID = optionID
        self.votedAt = votedAt
    }
}

public struct GroupMember: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var joinedAt: Date?
    /// This person's blacklisted places, scrambled per group (see
    /// `GroupBlacklist`). Nil for web voters and older app versions.
    public var blockedHashes: [String]?

    public init(id: String, name: String, joinedAt: Date? = nil, blockedHashes: [String]? = nil) {
        self.id = id
        self.name = name
        self.joinedAt = joinedAt
        self.blockedHashes = blockedHashes
    }
}
