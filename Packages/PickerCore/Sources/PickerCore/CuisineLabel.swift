import Foundation

/// A readable type for a place Apple Maps only calls "Restaurant", guessed
/// from its name: "Sam's Hot Dog Stand" → "Hot dogs", "Kangnam Style" → "Korean".
/// Nil when the name doesn't say (the place stays "Restaurant").
public enum CuisineLabel {
    /// Checked in order; the first rule with a matching word or phrase wins.
    /// Phrases are written with spaces and matched on whole words.
    static let rules: [(label: String, keys: [String])] = [
        ("Hot dogs", ["hot dog", "hot dogs", "hotdog", "hotdogs", "frank", "franks", "coney"]),
        ("Buffet", ["buffet"]),
        ("Korean", ["korean", "kangnam", "gangnam", "seoul", "kbbq", "bulgogi", "bibimbap", "kimchi"]),
        ("Ramen", ["ramen"]),
        ("Japanese", ["sushi", "hibachi", "japanese", "teppanyaki", "izakaya", "sashimi", "tokyo", "kyoto", "osaka"]),
        ("Vietnamese", ["pho", "vietnamese", "saigon", "banh mi", "hanoi"]),
        ("Thai", ["thai", "siam", "bangkok"]),
        ("Indian", ["indian", "curry", "tandoor", "tandoori", "masala", "biryani", "nepali", "himalayan"]),
        ("Chinese", ["chinese", "wok", "szechuan", "sichuan", "hunan", "peking", "shanghai", "dim sum",
                     "dumpling", "dumplings", "mandarin", "cantonese"]),
        ("Mexican", ["mexican", "taco", "tacos", "taqueria", "cantina", "burrito", "burritos", "tex mex",
                     "jalisco", "guadalajara", "azteca", "enchilada", "tamales"]),
        ("Latin", ["sabor", "latin", "latino", "cuban", "cubano", "peruvian", "colombian", "venezuelan",
                   "salvadoran", "arepa", "arepas", "empanada", "empanadas", "pupusa", "pupuseria",
                   "criollo", "criolla", "dominican", "puerto rican"]),
        ("Pizza", ["pizza", "pizzeria"]),
        ("Italian", ["italian", "trattoria", "ristorante", "osteria", "pasta"]),
        ("Burgers", ["burger", "burgers"]),
        ("BBQ", ["bbq", "barbecue", "smokehouse", "brisket"]),
        ("Steakhouse", ["steakhouse", "steak", "steaks", "chophouse"]),
        ("Seafood", ["seafood", "fish", "crab", "oyster", "oysters", "lobster", "shrimp", "crawfish", "poke"]),
        ("Chicken", ["chicken", "wings", "wing"]),
        ("Sandwiches", ["deli", "sandwich", "sandwiches", "subs", "hoagie", "cheesesteak"]),
        ("Mediterranean", ["mediterranean", "greek", "gyro", "gyros", "falafel", "shawarma", "kebab", "lebanese"]),
        ("Breakfast", ["breakfast", "brunch", "pancake", "pancakes", "waffle", "waffles", "diner"]),
        ("Dessert", ["ice cream", "creamery", "gelato", "dessert", "desserts", "frozen yogurt", "custard"]),
        ("Bakery", ["bakery", "donut", "donuts", "doughnut", "bagel", "bagels"]),
        ("Café", ["cafe", "coffee", "espresso", "tea house"]),
    ]

    public static func guess(name: String) -> String? {
        let padded = " " + FastFood.normalize(name.folding(options: .diacriticInsensitive, locale: nil)) + " "
        for rule in rules where rule.keys.contains(where: { padded.contains(" \($0) ") }) {
            return rule.label
        }
        // A chain with no food word in its name ("DQ Grill & Chill").
        return FastFood.isFastFood(name) ? "Fast food" : nil
    }
}
