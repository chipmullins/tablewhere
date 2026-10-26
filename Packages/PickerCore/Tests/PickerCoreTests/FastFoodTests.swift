import XCTest
@testable import PickerCore

final class FastCasualTests: XCTestCase {
    func testFastCasualChainsCountAsFastFood() {
        XCTAssertTrue(FastFood.isFastFood("Fazoli's"))
        XCTAssertTrue(FastFood.isFastFood("Chipotle Mexican Grill"))
        XCTAssertTrue(FastFood.isFastFood("Moe’s Southwest Grill"))
        XCTAssertTrue(FastFood.isFastFood("QDOBA Mexican Eats"))
        XCTAssertFalse(FastFood.isFastFood("Moe's Original BBQ"))
    }
}
