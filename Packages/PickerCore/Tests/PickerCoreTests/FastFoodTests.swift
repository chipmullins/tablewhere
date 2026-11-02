import XCTest
@testable import PickerCore

final class FastCasualTests: XCTestCase {
    func testPlacesThatCallThemselvesFastFoodCount() {
        XCTAssertTrue(FastFood.isFastFood("Grimes's Fast Food Restaurant"))
        XCTAssertTrue(FastFood.isFastFood("Fast-Food Express"))
        XCTAssertFalse(FastFood.isFastFood("Steakfast Foodhall"))
    }

    func testFastCasualChainsCountAsFastFood() {
        XCTAssertTrue(FastFood.isFastFood("Fazoli's"))
        XCTAssertTrue(FastFood.isFastFood("Chipotle Mexican Grill"))
        XCTAssertTrue(FastFood.isFastFood("Moe’s Southwest Grill"))
        XCTAssertTrue(FastFood.isFastFood("QDOBA Mexican Eats"))
        XCTAssertFalse(FastFood.isFastFood("Moe's Original BBQ"))
    }
}
