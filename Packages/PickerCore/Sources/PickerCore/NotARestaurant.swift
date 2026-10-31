import Foundation

/// Stores Apple Maps files under food (a grocery store's bakery, a gas
/// station, a pharmacy) that nobody means when they're picking where to eat.
/// Nearby searches drop them; searching for one by name still finds it.
public enum NotARestaurant {
    /// Matched at the start of the name, so "Walmart Bakery", "Kroger Deli"
    /// and "Kroger Marketplace" all count. Places inside them that have their
    /// own name ("Starbucks", "Subway") are unaffected. Only names that are
    /// unlikely to start a restaurant's name belong here.
    public static let prefixes: [String] = [
        // Grocery and warehouse
        "Kroger", "Walmart", "Wal-Mart", "Target", "Meijer", "Costco", "Sam's Club", "BJ's Wholesale",
        "Aldi", "Lidl", "Publix", "Whole Foods", "Trader Joe's", "Food Lion", "Safeway", "Albertsons",
        "Fresh Thyme", "Save A Lot", "Save-A-Lot", "Piggly Wiggly", "Giant Eagle", "Harris Teeter",
        "H-E-B", "Hy-Vee", "Jewel-Osco", "Fred Meyer", "King Soopers", "Winn-Dixie", "ShopRite",
        "Stop & Shop", "Wegmans", "Sprouts Farmers", "WinCo", "Schnucks", "Hannaford", "The Fresh Market",
        "Food 4 Less", "Grocery Outlet", "Weis Markets",
        // Pharmacy, dollar stores
        "CVS", "Walgreens", "Rite Aid", "Dollar General", "Dollar Tree", "Family Dollar",
        // Gas station chains with distinctive names
        "Circle K", "Speedway", "Thorntons", "7-Eleven", "Murphy USA", "Pilot Travel", "Pilot Flying J",
        "Love's Travel", "Flying J"
    ]

    /// Only when the whole name is exactly this (these words also start
    /// real restaurant names, like "Marathon Grill" or "Shell's Seafood").
    public static let exactNames: [String] = [
        "Shell", "BP", "Marathon", "Exxon", "Mobil", "Chevron", "Sunoco", "Valero", "Citgo",
        "Pilot", "Love's", "IGA", "Food City", "Ralphs", "Vons", "Dillons", "Smith's"
    ]

    private static let normalizedPrefixes = prefixes.map(FastFood.normalize)
    private static let normalizedExact = Set(exactNames.map(FastFood.normalize))

    public static func matches(_ name: String) -> Bool {
        let n = FastFood.normalize(name)
        if normalizedExact.contains(n) { return true }
        return normalizedPrefixes.contains { n == $0 || n.hasPrefix($0 + " ") }
    }
}
