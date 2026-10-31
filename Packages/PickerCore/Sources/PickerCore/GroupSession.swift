import Foundation

// Group decisions (Phase 2). These types are plain Codable values with no
// Firebase dependency, so the app, the iMessage extension, and the tests can
// all use them. The app stores them in Firestore with the same field names.

/// How a group decides.
public enum GroupMode: String, Codable, Sendable, CaseIterable {
    /// Everyone votes; most votes wins, ties are broken fairly.
    case vote
    /// Everyone adds a place; the app picks one at random.
    case spin
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
                winnerID: String? = nil, meetTime: Date? = nil, note: String? = nil) {
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
    public func canAdd(userID: String) -> Bool {
        guard status == .open, options.count < GroupSession.maxOptions else { return false }
        if mode == .vote && isOwned(by: userID) { return true }
        return pick(of: userID) == nil
    }

    /// Most places a group can hold.
    public static let maxOptions = 12
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

    public init(id: String, name: String, joinedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.joinedAt = joinedAt
    }
}
