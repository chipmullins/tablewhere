import XCTest
@testable import PickerCore

final class ArrivalBoardTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func time(_ d: Date) -> String { "\(Int(d.timeIntervalSince(t0) / 60))m" }

    func testLine() {
        let etas = [
            GroupETA(userID: "a", name: "Alex Smith", eta: t0.addingTimeInterval(12 * 60), status: .onTheWay),
            GroupETA(userID: "s", name: "Sam", eta: t0.addingTimeInterval(5 * 60), status: .onTheWay),
        ]
        let members = [GroupMember(id: "s", name: "Sam"), GroupMember(id: "a", name: "Alex Smith"),
                       GroupMember(id: "j", name: "Jo")]
        XCTAssertEqual(ArrivalBoard.line(etas: etas, members: members, me: nil, time: time),
                       "Sam ~5m · Alex ~12m · Jo hasn’t left")
    }

    func testArrivedLateAndYou() {
        let etas = [
            GroupETA(userID: "s", name: "Sam", eta: nil, status: .late, lateNote: "text"),
            GroupETA(userID: "a", name: "Alex", eta: t0, status: .arrived),
            GroupETA(userID: "me", name: "Chip", eta: t0.addingTimeInterval(60), status: .late, lateMinutes: 15),
        ]
        let members = [GroupMember(id: "me", name: "Chip")]
        XCTAssertEqual(ArrivalBoard.line(etas: etas, members: members, me: "me", time: time),
                       "Alex arrived · You ~15 min late · Sam running late")
    }

    func testOnlyYouLeft() {
        let etas = [GroupETA(userID: "s", name: "Sam", eta: t0, status: .arrived)]
        let members = [GroupMember(id: "s", name: "Sam"), GroupMember(id: "me", name: "Chip")]
        XCTAssertEqual(ArrivalBoard.line(etas: etas, members: members, me: "me", time: time),
                       "Sam arrived · you haven’t left")
    }

    func testNobody() {
        XCTAssertNil(ArrivalBoard.line(etas: [], members: [], me: nil, time: time))
    }
}
