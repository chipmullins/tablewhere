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

    /// Checked in order; the first rule with a matching word wins. Includes
    /// cuisine and place words ("Japanese", "Shanghai", "Kyoto", "Cinco") and
    /// well-known chains, since Apple Maps usually just says "Restaurant".
    private static let nameRules: [(CuisineIcon, Set<String>)] = [
        (.burrito, ["burrito", "burritos", "chipotle", "qdoba", "moes"]),
        (.taco, ["taco", "tacos", "taqueria", "cantina", "mexican", "mexicana", "mexicano", "cocina",
                 "tortilleria", "jalisco", "guadalajara", "azteca", "aztec", "fiesta", "amigos", "hacienda",
                 "cinco", "mayo", "texmex", "tex", "mex", "enchilada", "tamale", "tamales", "nacho", "nachos"]),
        (.ramen, ["ramen"]),
        (.sushi, ["sushi", "sake", "izakaya", "japanese", "japan", "kyoto", "tokyo", "osaka", "hibachi",
                  "teppanyaki", "sakura", "sashimi", "maki", "nigiri", "yakitori", "teriyaki"]),
        (.noodles, ["pho", "noodle", "noodles", "thai", "thailand", "bangkok", "siam", "wok", "dumpling",
                    "dumplings", "chinese", "china", "shanghai", "beijing", "peking", "szechuan", "sichuan",
                    "hunan", "canton", "cantonese", "mandarin", "panda", "asian", "asia", "vietnamese",
                    "vietnam", "saigon", "hanoi", "mein", "lo", "udon", "pad", "bao", "hong", "kong"]),
        (.pizza, ["pizza", "pizzas", "pizzeria", "italian", "italia", "italiano", "trattoria", "ristorante",
                  "osteria", "pasta", "napoli", "roma", "sicilian", "calzone", "fazolis", "dominos", "papa",
                  "marcos", "caesars", "sbarro"]),
        (.burger, ["burger", "burgers", "hamburger", "hamburgers", "mcdonalds", "wendys", "culvers",
                   "whataburger", "sonic", "checkers", "rallys", "hardees", "arbys", "shack", "drivein"]),
        (.curry, ["curry", "masala", "tandoor", "tandoori", "india", "indian", "nepal", "nepali",
                  "himalayan", "bombay", "mumbai", "delhi", "punjab", "punjabi", "taj", "biryani", "naan"]),
        (.bbq, ["bbq", "barbecue", "smokehouse", "smoke", "smokin", "smoked", "brisket", "ribs", "rib",
                "pit", "korean", "kbbq", "kalbi"]),
        (.steak, ["steak", "steaks", "steakhouse", "chophouse", "prime", "longhorn", "outback", "texas"]),
        (.seafood, ["fish", "oyster", "oysters", "crab", "seafood", "lobster", "shrimp", "crawfish",
                    "catfish", "cajun", "boil", "clam", "clams", "poke", "captain"]),
        (.chicken, ["chicken", "wings", "wing", "chick", "kfc", "popeyes", "canes", "bojangles", "zaxbys",
                    "wingstop", "fried", "rotisserie", "hen"]),
        (.sandwich, ["deli", "sandwich", "sandwiches", "subs", "sub", "subway", "hoagie", "hoagies",
                     "panini", "jimmy", "jersey", "potbelly", "firehouse", "quiznos", "cheesesteak"]),
        (.salad, ["salad", "salads", "vegan", "greens", "vegetarian", "veggie", "plant", "bowl",
                  "bowls", "mediterranean", "greek", "falafel", "gyro", "gyros"]),
        (.breakfast, ["breakfast", "pancake", "pancakes", "waffle", "waffles", "brunch", "diner", "egg",
                      "eggs", "biscuit", "biscuits", "ihop", "omelet", "omelette", "griddle", "skillet"]),
        (.dessert, ["creamery", "gelato", "dessert", "desserts", "sweets", "cupcake", "cupcakes", "yogurt",
                    "froyo", "custard", "frozen", "candy", "chocolate", "cookie", "cookies", "boba", "dairy"]),
        (.bakery, ["bakery", "bake", "bakehouse", "bread", "donut", "donuts", "doughnut", "doughnuts",
                   "croissant", "bagel", "bagels", "pastry", "patisserie", "krispy", "kreme"]),
        (.coffee, ["coffee", "espresso", "cafe", "roasters", "starbucks", "dunkin", "latte", "tea", "teahouse"]),
        (.beer, ["brew", "brewing", "brewery", "brewhouse", "taproom", "pub", "tavern", "bar", "alehouse",
                 "saloon", "sports", "ale", "beer"]),
        (.wine, ["wine", "vino", "winery", "vineyard", "cellar"]),
    ]

    /// Two-word phrases checked before single words.
    private static let phraseRules: [((String, String), CuisineIcon)] = [
        (("fast", "food"), .burger), (("ice", "cream"), .dessert), (("dim", "sum"), .noodles),
        (("lo", "mein"), .noodles), (("olive", "garden"), .pizza), (("waffle", "house"), .breakfast),
        (("cracker", "barrel"), .breakfast), (("first", "watch"), .breakfast), (("five", "guys"), .burger),
        (("burger", "king"), .burger), (("taco", "bell"), .taco), (("dairy", "queen"), .dessert),
        (("pizza", "hut"), .pizza), (("hot", "pot"), .noodles), (("red", "lobster"), .seafood),
        (("long", "john"), .seafood), (("jack", "box"), .burger), (("steak", "n"), .burger)
    ]

    /// Words that are too generic to decide on their own; only used when
    /// nothing more specific matches.
    private static let weakWords: Set<String> = ["bowl", "bowls", "lo", "pad", "hong", "kong",
                                                 "prime", "texas", "papa", "hen", "pit", "captain", "plant",
                                                 "sports", "tex", "mex", "jersey", "jimmy", "firehouse",
                                                 "dairy", "fried", "boil", "cellar", "smoke"]

    private static func fromName(_ words: [String]) -> CuisineIcon? {
        for (a, b) in zip(words, words.dropFirst()) {
            if let hit = phraseRules.first(where: { $0.0.0 == a && $0.0.1 == b }) { return hit.1 }
        }
        let strong = Set(words).subtracting(weakWords)
        for (icon, keys) in nameRules where !strong.isDisjoint(with: keys) {
            return icon
        }
        let weak = Set(words).intersection(weakWords)
        for (icon, keys) in nameRules where !weak.isDisjoint(with: keys) {
            return icon
        }
        // Known fast-food chains not listed above.
        if FastFood.isFastFood(words.joined(separator: " ")) { return .burger }
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
