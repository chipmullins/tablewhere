import Foundation

/// Counts votes and decides a winner.
///
/// Tie-breaks and spin results are deterministic for a given session ID, so
/// every device (and the web page) agrees on the same answer without a server
/// having to pick.
public struct Tally: Sendable {
    public let counts: [String: Int]
    public let votersByOption: [String: [String]]
    public let totalVotes: Int
    /// Option IDs with the most votes, in the session's option order.
    public let leaders: [String]

    public init(options: [GroupOption], votes: [GroupVote]) {
        let validIDs = Set(options.map(\.id))
        var counts: [String: Int] = [:]
        var voters: [String: [String]] = [:]
        for vote in votes where validIDs.contains(vote.optionID) {
            counts[vote.optionID, default: 0] += 1
            voters[vote.optionID, default: []].append(vote.voterName)
        }
        self.counts = counts
        self.votersByOption = voters
        self.totalVotes = counts.values.reduce(0, +)
        let top = counts.values.max() ?? 0
        self.leaders = top == 0 ? [] : options.map(\.id).filter { counts[$0] == top }
    }

    public func count(for optionID: String) -> Int { counts[optionID] ?? 0 }

    public var isTie: Bool { leaders.count > 1 }

    /// The single leader, if there is exactly one.
    public var leader: String? { leaders.count == 1 ? leaders[0] : nil }

    /// Winner for a vote: the leader, or a fair pick among tied leaders.
    public func voteWinner(sessionID: String) -> String? {
        guard !leaders.isEmpty else { return nil }
        return Tally.stablePick(from: leaders.sorted(), seed: sessionID)
    }

    /// Winner for spin mode: a fair pick among all options.
    public static func spinWinner(options: [GroupOption], sessionID: String) -> String? {
        stablePick(from: options.map(\.id).sorted(), seed: sessionID + "|spin")
    }

    /// Same input always gives the same pick (FNV-1a hash of the seed).
    static func stablePick(from ids: [String], seed: String) -> String? {
        guard !ids.isEmpty else { return nil }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return ids[Int(hash % UInt64(ids.count))]
    }
}

/// Six-character join codes without look-alike characters (no 0/O, 1/I/L).
public enum JoinCode {
    public static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    public static func make<G: RandomNumberGenerator>(using generator: inout G) -> String {
        String((0..<6).map { _ in alphabet.randomElement(using: &generator)! })
    }

    public static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return make(using: &generator)
    }

    /// Uppercases and strips spaces/dashes so "k7q-4mz" matches "K7Q4MZ".
    public static func normalize(_ input: String) -> String {
        input.uppercased().filter { alphabet.contains($0) }
    }

    /// "K7Q4MZ" → "K7Q·4MZ" for display.
    public static func display(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3))·\(code.suffix(3))"
    }
}

/// Web vote links: https://<host>/v/<sessionID>
public enum GroupLinks {
    public static func webURL(sessionID: String, host: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v/\(sessionID)"
        return components.url
    }

    public static func sessionID(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == "v", !parts[1].isEmpty else { return nil }
        return parts[1]
    }
}
