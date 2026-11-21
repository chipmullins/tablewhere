import XCTest
@testable import PickerCore

final class FastCasualTests: XCTestCase {
    func testPlacesThatCallThemselvesFastFoodCount() {
        XCTAssertTrue(FastFood.isFastFood("Grimes's Fast Food Restaurant"))
        XCTAssertTrue(FastFood.isFastFood("Fast-Food Express"))
        XCTAssertTrue(FastFood.isFastFood("Hunt Brothers Pizza"))
        XCTAssertTrue(FastFood.isFastFood("DQ Grill & Chill"))
        XCTAssertTrue(FastFood.isFastFood("Sam's Hot Dog Stand"))
        XCTAssertFalse(FastFood.isFastFood("DQuarters Bistro"))
        XCTAssertFalse(FastFood.isFastFood("Steakfast Foodhall"))
    }

    func testFastCasualChainsCountAsFastFood() {
        XCTAssertTrue(FastFood.isFastFood("Fazoli's"))
        XCTAssertTrue(FastFood.isFastFood("Chipotle Mexican Grill"))
        XCTAssertTrue(FastFood.isFastFood("Moe’s Southwest Grill"))
        XCTAssertTrue(FastFood.isFastFood("QDOBA Mexican Eats"))
        XCTAssertFalse(FastFood.isFastFood("Moe's Original BBQ"))
    }

    func testRegionalChainsNationwide() {
        XCTAssertTrue(FastFood.isFastFood("Taco John's"))
        XCTAssertTrue(FastFood.isFastFood("Cookout"))
        XCTAssertTrue(FastFood.isFastFood("Cook Out"))
        XCTAssertTrue(FastFood.isFastFood("Culver's"))
        XCTAssertTrue(FastFood.isFastFood("Whataburger"))
        XCTAssertTrue(FastFood.isFastFood("In-N-Out Burger"))
        XCTAssertTrue(FastFood.isFastFood("Braum's Ice Cream & Dairy Store"))
        XCTAssertTrue(FastFood.isFastFood("Slim Chickens"))
        XCTAssertTrue(FastFood.isFastFood("Dave's Hot Chicken"))
        XCTAssertTrue(FastFood.isFastFood("Pollo Tropical"))
        XCTAssertTrue(FastFood.isFastFood("Skyline Chili"))
        XCTAssertTrue(FastFood.isFastFood("Schlotzsky's"))
        XCTAssertTrue(FastFood.isFastFood("Jet's Pizza"))
        XCTAssertTrue(FastFood.isFastFood("Wawa"))
        XCTAssertFalse(FastFood.isFastFood("Cookhouse Grill"))
        XCTAssertFalse(FastFood.isFastFood("Skyline Steakhouse"))
        XCTAssertFalse(FastFood.isFastFood("The Habitat Cafe"))
    }

    func testLabelsFromNames() {
        XCTAssertEqual(CuisineLabel.guess(name: "Sam's Hot Dog Stand"), "Hot dogs")
        XCTAssertEqual(CuisineLabel.guess(name: "Flaming Grill Buffet"), "Buffet")
        XCTAssertEqual(CuisineLabel.guess(name: "Kangnam Style"), "Korean")
        XCTAssertEqual(CuisineLabel.guess(name: "Sabor A Miel"), "Latin")
        XCTAssertEqual(CuisineLabel.guess(name: "DQ Grill & Chill"), "Fast food")
        XCTAssertNil(CuisineLabel.guess(name: "The Blue Door"))
    }
}
