import Foundation

/// Recognizes fast-food chains by name.
///
/// MapKit doesn't tag restaurants as fast food, so we match against a list of
/// well-known chains, plus fast-casual counter-service chains (Chipotle,
/// Fazoli's, Moe's). Add or remove names in `chains`.
public enum FastFood {

    public static let chains: [String] = [
        "mcdonalds", "burger king", "wendys", "taco bell", "kfc", "kentucky fried chicken",
        "subway", "chick fil a", "arbys", "sonic drive in", "sonic", "popeyes",
        "jack in the box", "hardees", "carls jr", "dairy queen", "dominos", "pizza hut",
        "papa johns", "little caesars", "whataburger", "in n out", "zaxbys",
        "raising canes", "white castle", "krystal", "del taco", "checkers", "rallys",
        "long john silvers", "panda express", "wingstop", "jimmy johns", "bojangles",
        "churchs chicken", "churchs texas chicken", "captain ds", "steak n shake",
        "taco john", "a and w", "aw restaurant", "el pollo loco", "boston market",
        "golden corral", "marcos pizza", "hungry howies", "papa murphys", "jersey mikes",
        "firehouse subs", "potbelly", "quiznos", "blimpie", "dunkin", "tim hortons",
        "krispy kreme", "cook out", "culvers", "freddys frozen custard", "portillos",
        "hot n now", "jollibee", "biscuitville",
        // Fast casual: order at the counter, food in minutes.
        "fazolis", "chipotle", "moes southwest grill", "qdoba", "five guys", "shake shack",
        "smashburger", "freddys", "panera bread", "noodles and company", "cicis", "sbarro",
        "wienerschnitzel", "taco cabana", "chicken salad chick", "tropical smoothie cafe"
    ]

    private static let normalizedChains: [String] = chains.map(normalize)

    /// True when the name starts with a known chain name ("McDonald's #4021"
    /// and "Taco Bell Cantina" both match), or the place calls itself fast
    /// food ("Grimes's Fast Food Restaurant", a local spot no list would know).
    public static func isFastFood(_ name: String) -> Bool {
        let n = normalize(name)
        if (" " + n + " ").contains(" fast food ") { return true }
        return normalizedChains.contains { chain in
            n == chain || n.hasPrefix(chain + " ")
        }
    }

    /// Lowercase, "&" → "and", drop apostrophes, turn other punctuation into spaces.
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
        let spaced = lowered.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }
}
