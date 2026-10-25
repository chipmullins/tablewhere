import XCTest
@testable import PickerCore

final class GroupTests: XCTestCase {

    private func option(_ name: String) -> GroupOption {
        GroupOption(place: Place(name: name, category: "Restaurant", latitude: 38, longitude: -84.5, distanceMeters: 0),
                    addedBy: "Test")
    }

    private func vote(_ voter: String, for option: GroupOption) -> GroupVote {
        GroupVote(voterID: voter, voterName: voter, optionID: option.id)
    }

    func testClearWinner() {
        let a = option("A"), b = option("B")
        let tally = Tally(options: [a, b], votes: [vote("1", for: a), vote("2", for: a), vote("3", for: b)])
        XCTAssertEqual(tally.count(for: a.id), 2)
        XCTAssertEqual(tally.leader, a.id)
        XCTAssertFalse(tally.isTie)
        XCTAssertEqual(tally.voteWinner(sessionID: "s1"), a.id)
    }

    func testTieBreakIsStableAndPicksALeader() {
        let a = option("A"), b = option("B"), c = option("C")
        let tally = Tally(options: [a, b, c], votes: [vote("1", for: a), vote("2", for: b)])
        XCTAssertTrue(tally.isTie)
        let first = tally.voteWinner(sessionID: "session-xyz")
        XCTAssertNotNil(first)
        XCTAssertTrue([a.id, b.id].contains(first!))
        // Every device computes the same answer.
        for _ in 0..<20 { XCTAssertEqual(tally.voteWinner(sessionID: "session-xyz"), first) }
    }

    func testVotesForRemovedOptionsAreIgnored() {
        let a = option("A")
        let ghost = GroupVote(voterID: "1", voterName: "1", optionID: "missing")
        let tally = Tally(options: [a], votes: [ghost])
        XCTAssertEqual(tally.totalVotes, 0)
        XCTAssertNil(tally.voteWinner(sessionID: "s"))
    }

    func testSpinWinnerIsAnOption() {
        let options = [option("A"), option("B"), option("C")]
        let id = Tally.spinWinner(options: options, sessionID: "abc")
        XCTAssertTrue(options.map(\.id).contains(id!))
    }

    func testJoinCodes() {
        var gen = SeededGenerator(seed: 3)
        let code = JoinCode.make(using: &gen)
        XCTAssertEqual(code.count, 6)
        XCTAssertTrue(code.allSatisfy { JoinCode.alphabet.contains($0) })
        XCTAssertEqual(JoinCode.normalize("k7q-4mz"), "K7Q4MZ")
        XCTAssertEqual(JoinCode.display("K7Q4MZ"), "K7Q·4MZ")
    }

    func testWebLinksRoundTrip() {
        let url = GroupLinks.webURL(sessionID: "abc123", host: "forkroad.web.app")!
        XCTAssertEqual(url.absoluteString, "https://forkroad.web.app/v/abc123")
        XCTAssertEqual(GroupLinks.sessionID(from: url), "abc123")
        XCTAssertNil(GroupLinks.sessionID(from: URL(string: "https://forkroad.web.app/")!))
    }

    func testSessionCodableRoundTrip() throws {
        let session = GroupSession(id: "s", title: "Friday dinner", joinCode: "K7Q4MZ",
                                   createdBy: "u1", createdByName: "Chip", mode: .vote,
                                   options: [option("A")])
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(GroupSession.self, from: data)
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.options, session.options)
    }
}
