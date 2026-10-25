import XCTest
@testable import PickerCore

/// A seeded generator so tests get the same "random" results every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class RandomizerTests: XCTestCase {

    private func place(_ name: String, _ category: String, miles: Double) -> Place {
        Place(name: name, category: category, latitude: 38.0, longitude: -84.5,
              distanceMeters: miles * Place.metersPerMile)
    }

    private lazy var tacos = place("Juniper Taqueria", "Mexican", miles: 0.4)
    private lazy var ramen = place("Sora Ramen Bar", "Japanese", miles: 0.7)
    private lazy var steak = place("Oak Barrel", "Steak", miles: 7.8)

    func testBlockedPlaceIsNeverPicked() {
        let rules = Randomizer.Rules(blockedPlaceIDs: [tacos.id])
        XCTAssertEqual(Randomizer.eligible([tacos, ramen], rules: rules), [ramen])
    }

    func testBlockedCategoryIgnoresCase() {
        let rules = Randomizer.Rules(blockedCategories: ["mexican"])
        XCTAssertEqual(Randomizer.eligible([tacos, ramen], rules: rules), [ramen])
    }

    func testDistanceLimit() {
        let rules = Randomizer.Rules(maxDistanceMeters: 2 * Place.metersPerMile)
        XCTAssertEqual(Randomizer.eligible([tacos, ramen, steak], rules: rules), [tacos, ramen])
    }

    func testRecentPlacesAreAvoided() {
        var gen = SeededGenerator(seed: 42)
        let rules = Randomizer.Rules(recentPlaceIDs: [tacos.id])
        for _ in 0..<50 {
            XCTAssertEqual(Randomizer.pick(from: [tacos, ramen], rules: rules, using: &gen), ramen)
        }
    }

    func testFallsBackToRecentWhenNothingElseIsLeft() {
        var gen = SeededGenerator(seed: 7)
        let rules = Randomizer.Rules(recentPlaceIDs: [tacos.id])
        XCTAssertEqual(Randomizer.pick(from: [tacos], rules: rules, using: &gen), tacos)
    }

    func testEmptyPoolReturnsNil() {
        var gen = SeededGenerator(seed: 1)
        let rules = Randomizer.Rules(blockedPlaceIDs: [tacos.id])
        XCTAssertNil(Randomizer.pick(from: [tacos], rules: rules, using: &gen))
    }

    func testFastFoodMatching() {
        XCTAssertTrue(FastFood.isFastFood("McDonald's"))
        XCTAssertTrue(FastFood.isFastFood("Taco Bell Cantina"))
        XCTAssertTrue(FastFood.isFastFood("Chick-fil-A"))
        XCTAssertTrue(FastFood.isFastFood("Raising Cane’s Chicken Fingers"))
        XCTAssertFalse(FastFood.isFastFood("Sora Ramen Bar"))
        XCTAssertTrue(FastFood.isFastFood("Subway"))
        // Names that merely start with the same letters don't match.
        XCTAssertFalse(FastFood.isFastFood("Sonicraft Kitchen"))
        XCTAssertFalse(FastFood.isFastFood("Kfcake Bakery"))
    }

    func testExcludeFastFoodRule() {
        let mcd = place("McDonald's", "Restaurant", miles: 0.2)
        let rules = Randomizer.Rules(excludeFastFood: true)
        XCTAssertEqual(Randomizer.eligible([mcd, ramen], rules: rules), [ramen])
        XCTAssertEqual(Randomizer.eligible([mcd, ramen], rules: Randomizer.Rules()), [mcd, ramen])
    }

    func testStableIDsAcrossSearches() {
        let a = Place(name: "Sora Ramen Bar", category: "Japanese", latitude: 38.04061, longitude: -84.50372, distanceMeters: 100)
        let b = Place(name: "Sora Ramen Bar", category: "Restaurant", latitude: 38.04062, longitude: -84.50371, distanceMeters: 900)
        XCTAssertEqual(a.id, b.id)
    }
}
