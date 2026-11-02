import Foundation

/// Picks a random restaurant while respecting the user's rules.
public enum Randomizer {

    public struct Rules: Sendable {
        public var blockedPlaceIDs: Set<String>
        /// Category names, compared case-insensitively.
        public var blockedCategories: Set<String>
        /// Places picked recently. Avoided when possible, never required.
        public var recentPlaceIDs: Set<String>
        /// Places farther than this are left out. `nil` means no limit.
        public var maxDistanceMeters: Double?
        /// Leaves out known fast-food chains (see `FastFood`).
        public var excludeFastFood: Bool
        /// Leaves out coffee shops and sweets (see `CoffeeAndSweets`).
        public var excludeCoffeeAndSweets: Bool

        public init(
            blockedPlaceIDs: Set<String> = [],
            blockedCategories: Set<String> = [],
            recentPlaceIDs: Set<String> = [],
            maxDistanceMeters: Double? = nil,
            excludeFastFood: Bool = false,
            excludeCoffeeAndSweets: Bool = false
        ) {
            self.blockedPlaceIDs = blockedPlaceIDs
            self.blockedCategories = blockedCategories
            self.recentPlaceIDs = recentPlaceIDs
            self.maxDistanceMeters = maxDistanceMeters
            self.excludeFastFood = excludeFastFood
            self.excludeCoffeeAndSweets = excludeCoffeeAndSweets
        }
    }

    /// Places that pass the hard rules (blocked places, blocked categories, distance).
    /// Recent picks are still included here; `pick` handles them.
    public static func eligible(_ places: [Place], rules: Rules) -> [Place] {
        let blockedCats = Set(rules.blockedCategories.map { $0.lowercased() })
        return places.filter { place in
            if rules.blockedPlaceIDs.contains(place.id) { return false }
            if blockedCats.contains(place.category.lowercased()) { return false }
            if let max = rules.maxDistanceMeters, place.distanceMeters > max { return false }
            if rules.excludeFastFood && (FastFood.isFastFood(place.name) || place.category == "Fast food") { return false }
            if rules.excludeCoffeeAndSweets && CoffeeAndSweets.matches(name: place.name, category: place.category) { return false }
            return true
        }
    }

    /// Picks one place. Prefers places not picked recently, but falls back to
    /// recent ones rather than returning nothing.
    public static func pick<G: RandomNumberGenerator>(
        from places: [Place],
        rules: Rules,
        using generator: inout G
    ) -> Place? {
        let pool = eligible(places, rules: rules)
        let fresh = pool.filter { !rules.recentPlaceIDs.contains($0.id) }
        return (fresh.isEmpty ? pool : fresh).randomElement(using: &generator)
    }

    public static func pick(from places: [Place], rules: Rules) -> Place? {
        var generator = SystemRandomNumberGenerator()
        return pick(from: places, rules: rules, using: &generator)
    }
}
