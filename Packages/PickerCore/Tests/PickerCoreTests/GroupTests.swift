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

    func testCuisineSelectionHelpers() {
        XCTAssertEqual(CuisineFilter.ordered([]), [.all])
        XCTAssertEqual(CuisineFilter.ordered([.thai, .bbq, .mexican]), [.mexican, .bbq, .thai])
        XCTAssertEqual(CuisineFilter.summary(of: []), "all")
        XCTAssertEqual(CuisineFilter.summary(of: [.bbq, .mexican]), "Mexican, BBQ")
        XCTAssertEqual(CuisineFilter.summary(of: [.bbq, .mexican, .thai]), "Mexican, BBQ + 1 more")
        XCTAssertFalse(CuisineFilter.specific.contains(.all))
    }

    func testDietQueries() {
        XCTAssertEqual(DietFilter.none.query(for: .mexican), "Mexican restaurant")
        XCTAssertEqual(DietFilter.vegan.query(for: .mexican), "vegan Mexican restaurant")
        XCTAssertEqual(DietFilter.glutenFree.query(for: .all), "gluten free restaurant")
        XCTAssertFalse(DietFilter.specific.contains(.none))
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

final class PlanRSVPTests: XCTestCase {
    func testHeadcountCountsGuestsAndCreator() {
        let rsvps = [
            GroupRSVP(userID: "a", name: "Amy", going: true, guests: 2),
            GroupRSVP(userID: "b", name: "Ben", going: false, guests: 3),
        ]
        let count = RSVPCount(rsvps, creatorID: "host", creatorName: "Chip")
        XCTAssertEqual(count.people, 2)
        XCTAssertEqual(count.guests, 2)
        XCTAssertEqual(count.total, 4)
        XCTAssertEqual(count.notGoing.map(\.name), ["Ben"])
        XCTAssertEqual(count.summary, "4 coming (2 + 2 guests) · 1 can’t make it")
    }

    func testCreatorWhoSaysNoIsNotCounted() {
        let count = RSVPCount([GroupRSVP(userID: "host", name: "Chip", going: false)], creatorID: "host")
        XCTAssertEqual(count.total, 0)
    }

    func testGuestsAreClampedAndZeroWhenNotGoing() {
        XCTAssertEqual(GroupRSVP(userID: "a", name: "A", going: true, guests: 9).guests, GroupRSVP.maxGuests)
        XCTAssertEqual(GroupRSVP(userID: "a", name: "A", going: false, guests: 2).guests, 0)
    }

    func testPlanWinnerIsItsPlaceAndNobodyAdds() {
        let place = Place(id: "p", name: "Label", category: "Restaurant", latitude: 0, longitude: 0, distanceMeters: 0)
        let session = GroupSession(id: "s", title: "Dinner", joinCode: "ABC123", createdBy: "host",
                                   createdByName: "Chip", mode: .plan, status: .decided,
                                   options: [GroupOption(place: place, addedBy: "Chip")], winnerID: "p")
        XCTAssertEqual(session.pickWinner(votes: []), "p")
        XCTAssertFalse(session.canAdd(userID: "host"))
        XCTAssertFalse(session.rsvpOpen)
    }
}
