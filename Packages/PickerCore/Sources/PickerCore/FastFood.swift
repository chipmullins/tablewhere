import Foundation

/// Recognizes fast-food chains by name.
///
/// MapKit doesn't tag restaurants as fast food, so we match against a list of
/// well-known chains. Fast-casual places (Chipotle, Panera, Shake Shack) are
/// intentionally not on the list. Add or remove names in `chains`.
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
        "hot n now", "jollibee", "biscuitville"
    ]

    private static let normalizedChains: [String] = chains.map(normalize)

    /// True when the name starts with a known chain name
    /// ("McDonald's #4021" and "Taco Bell Cantina" both match).
    public static func isFastFood(_ name: String) -> Bool {
        let n = normalize(name)
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
