import XCTest
@testable import PickerCore

final class CuisineIconTests: XCTestCase {

    func testEveryIconHasAnAsset() {
        // One imageset per case in Shared/Resources/CuisineIcons.xcassets.
        XCTAssertEqual(CuisineIcon.allCases.count, 21)
        XCTAssertEqual(CuisineIcon.taco.assetName, "cuisine-taco")
        XCTAssertEqual(CuisineIcon.general.assetName, "cuisine-general")
    }

    func testCategories() {
        XCTAssertEqual(CuisineIcon.guess(name: "El Toro", category: "Mexican"), .taco)
        XCTAssertEqual(CuisineIcon.guess(name: "Sakura", category: "Japanese"), .sushi)
        XCTAssertEqual(CuisineIcon.guess(name: "Red State", category: "BBQ"), .bbq)
        XCTAssertEqual(CuisineIcon.guess(name: "Napoli", category: "Italian"), .pizza)
        XCTAssertEqual(CuisineIcon.guess(name: "Goodfellas", category: "Pizza"), .pizza)
        XCTAssertEqual(CuisineIcon.guess(name: "Shake Shack", category: "Burgers"), .burger)
        XCTAssertEqual(CuisineIcon.guess(name: "Golden Dragon", category: "Chinese"), .noodles)
        XCTAssertEqual(CuisineIcon.guess(name: "Siam", category: "Thai"), .noodles)
        XCTAssertEqual(CuisineIcon.guess(name: "Taj", category: "Indian"), .curry)
        XCTAssertEqual(CuisineIcon.guess(name: "A Cup of Commonwealth", category: "Café"), .coffee)
        XCTAssertEqual(CuisineIcon.guess(name: "Doughp", category: "Bakery"), .bakery)
        XCTAssertEqual(CuisineIcon.guess(name: "West Sixth", category: "Brewery"), .beer)
        XCTAssertEqual(CuisineIcon.guess(name: "Talon", category: "Winery"), .wine)
        XCTAssertEqual(CuisineIcon.guess(name: "Sprout", category: "Vegan"), .salad)
        XCTAssertEqual(CuisineIcon.guess(name: "Harbor", category: "Seafood"), .seafood)
    }

    func testCategoryWinsOverName() {
        // A specific category beats a name keyword...
        XCTAssertEqual(CuisineIcon.guess(name: "Taco Pizza Co", category: "Italian"), .pizza)
        // ...except a Japanese place that says ramen.
        XCTAssertEqual(CuisineIcon.guess(name: "Ramen Bar Ichiban", category: "Japanese"), .ramen)
    }

    func testGenericCategoryUsesName() {
        XCTAssertEqual(CuisineIcon.guess(name: "Taqueria Ramirez", category: "Restaurant"), .taco)
        XCTAssertEqual(CuisineIcon.guess(name: "Chuy's Burritos", category: ""), .burrito)
        XCTAssertEqual(CuisineIcon.guess(name: "Pho Saigon", category: "Restaurant"), .noodles)
        XCTAssertEqual(CuisineIcon.guess(name: "Blaze Pizza", category: "Restaurant"), .pizza)
        XCTAssertEqual(CuisineIcon.guess(name: "Izakaya Hana", category: ""), .sushi)
        XCTAssertEqual(CuisineIcon.guess(name: "Sonny's Smokehouse", category: "Restaurant"), .bbq)
        XCTAssertEqual(CuisineIcon.guess(name: "Malone's Steakhouse", category: "Restaurant"), .steak)
        XCTAssertEqual(CuisineIcon.guess(name: "Red Lobster", category: "Restaurant"), .seafood)
        XCTAssertEqual(CuisineIcon.guess(name: "Buffalo Wild Wings", category: "Restaurant"), .chicken)
        XCTAssertEqual(CuisineIcon.guess(name: "Jersey Mike's Subs", category: "Restaurant"), .sandwich)
        XCTAssertEqual(CuisineIcon.guess(name: "Original Pancake House", category: "Restaurant"), .breakfast)
        XCTAssertEqual(CuisineIcon.guess(name: "Crank & Boom Ice Cream", category: "Restaurant"), .dessert)
        XCTAssertEqual(CuisineIcon.guess(name: "Spalding's Donuts", category: "Restaurant"), .bakery)
        XCTAssertEqual(CuisineIcon.guess(name: "Country Boy Brewing", category: ""), .beer)
        XCTAssertEqual(CuisineIcon.guess(name: "Vino Vino", category: ""), .wine)
    }

    func testUnknownCategoryFallsBackToName() {
        XCTAssertEqual(CuisineIcon.guess(name: "Masala Grill", category: "Nightlife"), .curry)
    }

    func testCaseAndAccents() {
        XCTAssertEqual(CuisineIcon.guess(name: "Café Lumière", category: "Restaurant"), .coffee)
        XCTAssertEqual(CuisineIcon.guess(name: "SUSHI ZEN", category: ""), .sushi)
        XCTAssertEqual(CuisineIcon.guess(name: "Le Café", category: "CAFÉ"), .coffee)
    }

    func testWholeWordsOnly() {
        XCTAssertEqual(CuisineIcon.guess(name: "Subaru Grill", category: "Restaurant"), .general)
        XCTAssertEqual(CuisineIcon.guess(name: "Publix Deli Counter", category: ""), .sandwich)
        XCTAssertEqual(CuisineIcon.guess(name: "Publico", category: ""), .general)
        XCTAssertEqual(CuisineIcon.guess(name: "Greenfield Grill", category: ""), .general)
        XCTAssertEqual(CuisineIcon.guess(name: "Thaiphoon", category: ""), .general)
        XCTAssertEqual(CuisineIcon.guess(name: "Winery Road Diner", category: ""), .breakfast)
    }

    func testFallback() {
        XCTAssertEqual(CuisineIcon.guess(name: "The Merrick Inn", category: "Restaurant"), .general)
        XCTAssertEqual(CuisineIcon.guess(name: "", category: ""), .general)
        XCTAssertEqual(CuisineIcon.guess(name: "Holly Hill Inn", category: "American"), .general)
    }
}
