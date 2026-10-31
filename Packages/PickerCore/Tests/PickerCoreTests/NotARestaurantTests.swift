import XCTest
@testable import PickerCore

final class NotARestaurantTests: XCTestCase {
    func testGroceryAndGasAreDropped() {
        XCTAssertTrue(NotARestaurant.matches("Kroger"))
        XCTAssertTrue(NotARestaurant.matches("Walmart Bakery"))
        XCTAssertTrue(NotARestaurant.matches("Kroger Marketplace Deli"))
        XCTAssertTrue(NotARestaurant.matches("Sam’s Club Café"))
        XCTAssertTrue(NotARestaurant.matches("Speedway"))
    }

    func testRestaurantsStay() {
        XCTAssertFalse(NotARestaurant.matches("Starbucks"))
        XCTAssertFalse(NotARestaurant.matches("Targeted Tacos"))
        XCTAssertFalse(NotARestaurant.matches("Shellfish Shack"))
        XCTAssertFalse(NotARestaurant.matches("Pilot House Pizza Co"))
        XCTAssertFalse(NotARestaurant.matches("Marathon Grill"))
        XCTAssertTrue(NotARestaurant.matches("Marathon"))
    }
}
