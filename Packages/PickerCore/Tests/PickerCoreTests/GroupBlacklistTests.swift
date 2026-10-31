import XCTest
@testable import PickerCore

final class GroupBlacklistTests: XCTestCase {
    private func option(_ name: String) -> GroupOption {
        GroupOption(place: Place(name: name, category: "Restaurant", latitude: 38, longitude: -84.5, distanceMeters: 0),
                    addedBy: "Test")
    }

    private func session(_ mode: GroupMode, _ options: [GroupOption]) -> GroupSession {
        GroupSession(id: "s1", title: "Dinner", joinCode: "ABC123", createdBy: "owner",
                     createdByName: "Chip", mode: mode, options: options)
    }

    func testHashIsStablePerGroupAndDiffersAcrossGroups() {
        let a = GroupBlacklist.hash(placeID: "sora|38.0|-84.5", sessionID: "s1")
        XCTAssertEqual(a, GroupBlacklist.hash(placeID: "sora|38.0|-84.5", sessionID: "s1"))
        XCTAssertNotEqual(a, GroupBlacklist.hash(placeID: "sora|38.0|-84.5", sessionID: "s2"))
        XCTAssertEqual(a.count, 16)
        // Same value as the web page computes (SHA-256 of "s1|abc", first 8 bytes in hex).
        XCTAssertEqual(GroupBlacklist.hash(placeID: "abc", sessionID: "s1"), "dcee5aca160de97d")
    }

    func testRuledOutPlaceCantWinAVote() {
        let a = option("A"), b = option("B")
        let s = session(.vote, [a, b])
        let amy = GroupMember(id: "amy", name: "Amy",
                              blockedHashes: [GroupBlacklist.hash(placeID: a.id, sessionID: "s1")])
        let ruledOut = s.ruledOutIDs(members: [amy])
        XCTAssertEqual(ruledOut, [a.id])
        let votes = [GroupVote(voterID: "1", voterName: "1", optionID: a.id),
                     GroupVote(voterID: "2", voterName: "2", optionID: a.id),
                     GroupVote(voterID: "3", voterName: "3", optionID: b.id)]
        XCTAssertEqual(s.pickWinner(votes: votes, ruledOut: ruledOut), b.id)
        XCTAssertEqual(s.pickWinner(votes: votes), a.id)
    }

    func testSpinSkipsRuledOutAndNeverComesUpEmpty() {
        let a = option("A"), b = option("B")
        let s = session(.spin, [a, b])
        for _ in 0..<5 { XCTAssertEqual(s.pickWinner(votes: [], ruledOut: [a.id]), b.id) }
        XCTAssertNotNil(s.pickWinner(votes: [], ruledOut: [a.id, b.id]))
    }

    func testWaitingOnPicks() {
        var s = session(.spin, [option("A")])
        s.picksBy = ["owner": s.options[0].id]
        let members = [GroupMember(id: "owner", name: "Chip"), GroupMember(id: "amy", name: "Amy")]
        XCTAssertEqual(s.waitingOnPicks(members: members).map(\.name), ["Amy"])
        XCTAssertTrue(session(.vote, []).waitingOnPicks(members: members).isEmpty)
    }
}
