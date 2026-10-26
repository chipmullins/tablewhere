import Foundation
import PickerCore

/// Small JSON snapshots the app writes so the iMessage extension can offer
/// places without running its own location search.
enum SharedCache {
    private static let nearbyKey = "cache.nearby"
    private static let interestedKey = "cache.interested"
    private static let favoritesKey = "cache.favorites"
    private static let blockedKey = "cache.blockedIDs"
    private static let blockedCategoriesKey = "cache.blockedCategories"
    private static let sessionsKey = "cache.recentSessions"

    static func saveNearby(_ places: [Place]) { save(Array(places.prefix(25)), key: nearbyKey) }
    static func loadNearby() -> [Place] { load(key: nearbyKey) }

    static func saveInterested(_ places: [Place]) { save(places, key: interestedKey) }
    static func loadInterested() -> [Place] { load(key: interestedKey) }

    static func saveFavorites(_ places: [Place]) { save(places, key: favoritesKey) }
    static func loadFavorites() -> [Place] { load(key: favoritesKey) }

    /// Blacklist, so the widget and Siri never suggest a blacklisted place.
    static func saveBlocked(placeIDs: [String], categories: [String]) {
        SharedDefaults.store.set(placeIDs, forKey: blockedKey)
        SharedDefaults.store.set(categories, forKey: blockedCategoriesKey)
    }

    /// The widget/Siri rules: blacklist plus the "No fast food" setting.
    static func pickRules() -> Randomizer.Rules {
        Randomizer.Rules(
            blockedPlaceIDs: Set(SharedDefaults.store.stringArray(forKey: blockedKey) ?? []),
            blockedCategories: Set(SharedDefaults.store.stringArray(forKey: blockedCategoriesKey) ?? []),
            excludeFastFood: Preferences.excludeFastFood
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
