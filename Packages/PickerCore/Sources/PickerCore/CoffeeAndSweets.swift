import Foundation

/// Coffee shops and sweets (donuts, ice cream, froyo, boba, cookies): real
/// places, but not dinner. Hidden from nearby results and spins unless you
/// turn "No coffee & sweets" off. Your own saved places are never hidden.
///
/// Matched by name, like `FastFood`, because Apple's "café" category also
/// covers plenty of real restaurants (brunch spots, "Café Something" bistros),
/// and those should stay.
public enum CoffeeAndSweets {

    /// Chains, matched at the start of the name ("Starbucks Reserve", "Dutch Bros Coffee").
    public static let chains: [String] = [
        "starbucks", "dutch bros", "caribou coffee", "scooters coffee", "biggby", "peets coffee",
        "dunkin", "tim hortons", "krispy kreme", "duck donuts", "shipley do nuts", "shipley donuts",
        "baskin robbins", "cold stone", "marble slab", "menchies", "yogurtland", "sweet frog",
        "sweetfrog", "ritas", "graeters", "handels", "jenis", "insomnia cookies", "crumbl",
        "nothing bundt cakes", "smoothie king", "jamba", "kung fu tea", "gong cha", "sharetea",
        "tiger sugar", "teavana", "cinnabon", "auntie annes", "great american cookies"
    ]

    /// Words or phrases anywhere in the name that mean a coffee or sweets stop.
    /// Plain "cafe" and "bakery" aren't here on purpose: those are often meals.
    public static let nameWords: [String] = [
        "coffee", "espresso", "roasters", "roastery", "coffeehouse", "coffee house",
        "teahouse", "tea house", "bubble tea", "boba",
        "donut", "donuts", "doughnut", "doughnuts", "do nuts",
        "ice cream", "creamery", "gelato", "gelateria", "frozen yogurt", "froyo", "frozen custard",
        "cupcake", "cupcakes", "cookie", "cookies", "smoothie", "smoothies", "juice bar",
        "dessert", "desserts", "sweets", "candy", "chocolatier", "snow cone", "shaved ice"
    ]

    private static let normalizedChains = chains.map(FastFood.normalize)
    private static let normalizedWords = nameWords.map(FastFood.normalize)

    public static func matches(name: String, category: String = "") -> Bool {
        let n = FastFood.normalize(name.folding(options: .diacriticInsensitive, locale: nil))
        if normalizedChains.contains(where: { n == $0 || n.hasPrefix($0 + " ") }) { return true }
        let padded = " " + n + " "
        if normalizedWords.contains(where: { padded.contains(" \($0) ") }) { return true }
        // Labeled dessert from its name or a search (see CuisineLabel).
        return category == "Dessert"
    }
}
