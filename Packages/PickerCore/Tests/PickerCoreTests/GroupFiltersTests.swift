import XCTest
@testable import PickerCore

final class GroupFiltersTests: XCTestCase {
    private func option(_ name: String, _ category: String = "Restaurant") -> GroupOption {
        GroupOption(place: Place(name: name, category: category, latitude: 38, longitude: -84.5, distanceMeters: 0),
                    addedBy: "Test")
    }

    private func session(_ options: [GroupOption], filters: GroupFilters?, mode: GroupMode = .spin) -> GroupSession {
        GroupSession(id: "s1", title: "Dinner", joinCode: "ABC123", createdBy: "owner",
                     createdByName: "Chip", mode: mode, options: options, groupFilters: filters)
    }

    func testRules() {
        let both = GroupFilters(noFastFood: true, noCoffeeSweets: true)
        XCTAssertEqual(both.rule(name: "McDonald's", category: "Burgers"), "no fast food")
        XCTAssertEqual(both.rule(name: "Some Place", category: "Fast food"), "no fast food")
        XCTAssertEqual(both.rule(name: "Starbucks", category: "Café"), "no coffee & sweets")
        XCTAssertNil(both.rule(name: "Sora Ramen", category: "Ramen"))
        XCTAssertNil(GroupFilters().rule(name: "McDonald's", category: "Fast food"))
        XCTAssertNil(GroupFilters(noCoffeeSweets: true).rule(name: "McDonald's", category: "Burgers"))
        XCTAssertFalse(GroupFilters().isActive)
        XCTAssertEqual(GroupFilters(noFastFood: true).summary, "No fast food in this group")
    }

    func testBreakingPlacesAreRuledOut() {
        let ramen = option("Sora Ramen"), mcd = option("McDonald's")
        let s = session([ramen, mcd], filters: GroupFilters(noFastFood: true))
        XCTAssertEqual(s.filteredOutIDs, [mcd.id])
        XCTAssertEqual(s.ruledOutIDs(members: []), [mcd.id])
        XCTAssertEqual(s.pickWinner(votes: [], ruledOut: s.ruledOutIDs(members: [])), ramen.id)
    }

    func testEverythingBreakingMeansNothingIsRuledOut() {
        let s = session([option("McDonald's"), option("Wendy's")], filters: GroupFilters(noFastFood: true))
        XCTAssertEqual(s.ruledOutIDs(members: []), [])
        XCTAssertTrue(s.everythingRuledOut(members: []))
    }

    func testNoFiltersNothingRuledOut() {
        let s = session([option("Sora Ramen"), option("McDonald's")], filters: nil)
        XCTAssertEqual(s.ruledOutIDs(members: []), [])
    }

    func testFilterRuleForPicker() {
        let s = session([], filters: GroupFilters(noFastFood: true))
        let place = Place(name: "Taco Bell", category: "Mexican", latitude: 0, longitude: 0, distanceMeters: 0)
        XCTAssertEqual(s.filterRule(for: place), "no fast food")
        let plan = session([], filters: GroupFilters(noFastFood: true), mode: .plan)
        XCTAssertNil(plan.filterRule(for: place))
    }

    func testDecodesMissingKeysAsOff() throws {
        let decoded = try JSONDecoder().decode(GroupFilters.self, from: Data(#"{"noFastFood":true}"#.utf8))
        XCTAssertEqual(decoded, GroupFilters(noFastFood: true, noCoffeeSweets: false))
    }
}
