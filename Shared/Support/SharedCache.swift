import Foundation
import CoreLocation
import PickerCore

/// Where (and with which filters) the app last searched. The group pickers
/// start from it, and the iMessage extension searches around its center.
struct SearchArea: Equatable, Codable, Sendable {
    var latitude: Double
    var longitude: Double
    var radiusMiles: Double
    var cuisineIDs: [String]
    var dietID: String

    init(center: CLLocationCoordinate2D, radiusMiles: Double,
         cuisines: Set<CuisineFilter>, diet: DietFilter) {
        latitude = center.latitude
        longitude = center.longitude
        self.radiusMiles = radiusMiles
        cuisineIDs = CuisineFilter.ordered(cuisines).filter { $0 != .all }.map(\.rawValue)
        dietID = diet.rawValue
    }

    var center: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var cuisines: Set<CuisineFilter> { Set(cuisineIDs.compactMap(CuisineFilter.init(rawValue:))) }
    var diet: DietFilter { DietFilter(rawValue: dietID) ?? .none }
}

/// Small JSON snapshots the app writes so the iMessage extension can offer
/// places without running its own location search.
enum SharedCache {
    private static let nearbyKey = "cache.nearby"
    private static let interestedKey = "cache.interested"
    private static let favoritesKey = "cache.favorites"
    private static let blockedKey = "cache.blockedIDs"
    private static let blockedCategoriesKey = "cache.blockedCategories"
    private static let sessionsKey = "cache.recentSessions"
    private static let searchAreaKey = "cache.searchArea"

    static func saveSearchArea(_ area: SearchArea) {
        guard let data = try? JSONEncoder().encode(area) else { return }
        SharedDefaults.store.set(data, forKey: searchAreaKey)
    }

    static func loadSearchArea() -> SearchArea? {
        guard let data = SharedDefaults.store.data(forKey: searchAreaKey) else { return nil }
        return try? JSONDecoder().decode(SearchArea.self, from: data)
    }

    /// The app's last nearby search, for the widget, Siri, and the iMessage app.
    /// Searches now return 100+ places; 200 is plenty and stays small (~60 KB).
    static func saveNearby(_ places: [Place]) { save(Array(places.prefix(200)), key: nearbyKey) }
    static func loadNearby() -> [Place] { load(key: nearbyKey) }
    /// The widget and Siri pick from the closest places, not the whole radius
    /// (the list is nearest first).
    static func loadClosestNearby() -> [Place] { Array(loadNearby().prefix(40)) }

    static func saveInterested(_ places: [Place]) { save(places, key: interestedKey) }
    static func loadInterested() -> [Place] { load(key: interestedKey) }

    static func saveFavorites(_ places: [Place]) { save(places, key: favoritesKey) }
    static func loadFavorites() -> [Place] { load(key: favoritesKey) }

    /// Blacklist, so the widget and Siri never suggest a blacklisted place.
    static func saveBlocked(placeIDs: [String], categories: [String]) {
        SharedDefaults.store.set(placeIDs, forKey: blockedKey)
        SharedDefaults.store.set(categories, forKey: blockedCategoriesKey)
    }

    /// Your blacklisted place IDs (shared, scrambled, with groups you join).
    static func blockedPlaceIDs() -> [String] {
        SharedDefaults.store.stringArray(forKey: blockedKey) ?? []
    }

    /// The widget/Siri rules: blacklist plus the "No fast food" and "No coffee
    /// & sweets" settings. Pass `savedList: true` for your own lists, which
    /// keep the coffee shops you saved on purpose.
    static func pickRules(savedList: Bool = false) -> Randomizer.Rules {
        Randomizer.Rules(
            blockedPlaceIDs: Set(SharedDefaults.store.stringArray(forKey: blockedKey) ?? []),
            blockedCategories: Set(SharedDefaults.store.stringArray(forKey: blockedCategoriesKey) ?? []),
            excludeFastFood: Preferences.excludeFastFood,
            excludeCoffeeAndSweets: !savedList && Preferences.excludeCoffeeAndSweets
        )
    }

    // MARK: Recent group sessions (newest first)

    static func rememberSession(_ id: String) {
        var ids = recentSessionIDs().filter { $0 != id }
        ids.insert(id, at: 0)
        SharedDefaults.store.set(Array(ids.prefix(10)), forKey: sessionsKey)
    }

    static func recentSessionIDs() -> [String] {
        SharedDefaults.store.stringArray(forKey: sessionsKey) ?? []
    }

    static func forgetSession(_ id: String) {
        SharedDefaults.store.set(recentSessionIDs().filter { $0 != id }, forKey: sessionsKey)
    }

    // MARK: Helpers

    private static func save(_ places: [Place], key: String) {
        guard let data = try? JSONEncoder().encode(places) else { return }
        SharedDefaults.store.set(data, forKey: key)
    }

    private static func load(key: String) -> [Place] {
        guard let data = SharedDefaults.store.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Place].self, from: data)) ?? []
    }
}
