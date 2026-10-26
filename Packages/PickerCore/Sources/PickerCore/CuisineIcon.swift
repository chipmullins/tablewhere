import Foundation

/// The small cuisine pictures shown on restaurant rows in place of a letter tile.
///
/// MapKit gives no photos, so a row gets an icon guessed from the place's
/// category and name. Each case has a template image `cuisine-<rawValue>` in
/// the app's CuisineIcons asset catalog.
public enum CuisineIcon: String, CaseIterable, Sendable {
    case taco, burrito, ramen, noodles, pizza, burger, sushi, curry, bbq, steak
    case seafood, chicken, sandwich, salad, breakfast, coffee, bakery, dessert, beer, wine
    case general

    /// The asset catalog image name.
    public var assetName: String { "cuisine-\(rawValue)" }

    /// Picks an icon: a specific category wins, then keywords in the name,
    /// then `.general`. A category of "Restaurant" (or none) tells us nothing,
    /// so the name decides. Japanese places become ramen when the name says so.
    public static func guess(name: String, category: String) -> CuisineIcon {
        let words = Self.words(in: name)
        let fromName = Self.fromName(words)
        let cat = Self.normalize(category).trimmingCharacters(in: .whitespacesAndNewlines)

        if let fromCategory = Self.fromCategory(cat) {
            if fromCategory == .sushi, fromName == .ramen { return .ramen }
            return fromCategory
        }
        return fromName ?? .general
    }

    // MARK: - Category

    private static let categoryMap: [String: CuisineIcon] = [
        "mexican": .taco, "tex-mex": .taco, "taqueria": .taco,
        "japanese": .sushi, "sushi": .sushi, "ramen": .ramen,
        "bbq": .bbq, "barbecue": .bbq,
        "italian": .pizza, "pizza": .pizza, "pizzeria": .pizza,
        "burgers": .burger, "burger": .burger,
        "chinese": .noodles, "thai": .noodles, "vietnamese": .noodles, "noodles": .noodles,
        "indian": .curry,
        "cafe": .coffee, "coffee": .coffee, "coffee shop": .coffee,
        "bakery": .bakery,
        "brewery": .beer, "bar": .beer, "pub": .beer,
        "winery": .wine, "wine bar": .wine,
        "vegetarian": .salad, "vegan": .salad, "salad": .salad,
        "seafood": .seafood,
        "steakhouse": .steak, "steak": .steak,
        "chicken": .chicken,
        "sandwiches": .sandwich, "deli": .sandwich,
        "breakfast": .breakfast, "brunch": .breakfast, "diner": .breakfast,
        "dessert": .dessert, "ice cream": .dessert,
    ]

    private static func fromCategory(_ cat: String) -> CuisineIcon? {
        if cat.isEmpty || cat == "restaurant" || cat == "restaurants" || cat == "food" { return nil }
        if let hit = categoryMap[cat] { return hit }
        // "Mexican Restaurant", "Thai food": match the first word that is a category.
        for word in words(in: cat) {
            if let hit = categoryMap[word] { return hit }
        }
        return nil
    }

    // MARK: - Name keywords

    /// Checked in order; the first rule with a matching word wins.
    private static let nameRules: [(CuisineIcon, Set<String>)] = [
        (.burrito, ["burrito", "burritos"]),
        (.taco, ["taco", "tacos", "taqueria", "cantina"]),
        (.ramen, ["ramen"]),
        (.sushi, ["sushi", "sake", "izakaya"]),
        (.noodles, ["pho", "noodle", "noodles", "thai", "wok", "dumpling", "dumplings"]),
        (.pizza, ["pizza", "pizzas", "pizzeria"]),
        (.burger, ["burger", "burgers"]),
        (.curry, ["curry", "masala", "tandoor", "tandoori", "india", "indian"]),
        (.bbq, ["bbq", "barbecue", "smokehouse", "smoke", "smokin"]),
        (.steak, ["steak", "steaks", "steakhouse", "chophouse"]),
        (.seafood, ["fish", "oyster", "oysters", "crab", "seafood", "lobster"]),
        (.chicken, ["chicken", "wings", "wing"]),
        (.sandwich, ["deli", "sandwich", "sandwiches", "subs", "sub"]),
        (.salad, ["salad", "salads", "vegan", "green", "greens"]),
        (.breakfast, ["breakfast", "pancake", "pancakes", "waffle", "waffles", "brunch", "diner"]),
        (.dessert, ["creamery", "gelato", "dessert", "desserts", "sweets", "cupcake", "cupcakes"]),
        (.bakery, ["bakery", "bake", "bakehouse", "bread", "donut", "donuts", "doughnut", "doughnuts", "croissant"]),
        (.coffee, ["coffee", "espresso", "cafe", "roasters"]),
        (.beer, ["brew", "brewing", "brewery", "taproom", "pub", "tavern"]),
        (.wine, ["wine", "vino", "winery"]),
    ]

    private static func fromName(_ words: [String]) -> CuisineIcon? {
        let set = Set(words)
        // Two-word phrase.
        for (a, b) in zip(words, words.dropFirst()) where a == "ice" && b == "cream" {
            return .dessert
        }
        for (icon, keys) in nameRules where !set.isDisjoint(with: keys) {
            return icon
        }
        return nil
    }

    // MARK: - Text helpers

    /// Lowercased, accents removed ("Café" → "cafe").
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    /// Whole words only, so "Subaru" never matches "sub". Apostrophes are
    /// dropped so "Joe's" stays one word.
    private static func words(in text: String) -> [String] {
        normalize(text)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
