import XCTest
@testable import PickerCore

final class CoffeeAndSweetsTests: XCTestCase {
    func testCoffeeAndSweetsAreCaught() {
        for name in ["Starbucks", "Starbucks Reserve", "Dutch Bros Coffee", "Joe's Coffee House",
                     "Common Grounds Roasters", "Duck Donuts", "Crank & Boom Ice Cream", "Sweet Frog",
                     "Kung Fu Tea", "Crumbl Cookies"] {
            XCTAssertTrue(CoffeeAndSweets.matches(name: name), name)
        }
    }

    func testRealMealsStay() {
        for name in ["Café Jennifer", "Le Bistro Café", "Tatsu Sushi", "The Breakfast Club Bakery & Grill",
                     "Teazer's Grill", "Starlight Diner"] {
            XCTAssertFalse(CoffeeAndSweets.matches(name: name), name)
        }
    }

    func testRuleHidesThemOnlyWhenOn() {
        let place = Place(name: "Starbucks", category: "Café", latitude: 0, longitude: 0, distanceMeters: 0)
        XCTAssertEqual(Randomizer.eligible([place], rules: .init()).count, 1)
        XCTAssertEqual(Randomizer.eligible([place], rules: .init(excludeCoffeeAndSweets: true)).count, 0)
    }
}
