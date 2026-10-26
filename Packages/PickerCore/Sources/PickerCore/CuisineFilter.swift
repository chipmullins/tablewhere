import Foundation

/// The cuisine chips on Discover.
///
/// MapKit only knows broad categories like "restaurant" or "cafe", not cuisines,
/// so each filter becomes a search phrase ("Mexican restaurant") instead.
public enum CuisineFilter: String, CaseIterable, Identifiable, Sendable {
    case all, mexican, japanese, bbq, italian, pizza, burgers, chinese, thai, indian, cafe

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "All"
        case .mexican: return "Mexican"
        case .japanese: return "Japanese"
        case .bbq: return "BBQ"
        case .italian: return "Italian"
        case .pizza: return "Pizza"
        case .burgers: return "Burgers"
        case .chinese: return "Chinese"
        case .thai: return "Thai"
        case .indian: return "Indian"
        case .cafe: return "Café"
        }
    }

    /// The cuisines shown as chips (everything except "All").
    public static var specific: [CuisineFilter] { allCases.filter { $0 != .all } }

    /// Most cuisines you can combine at once. Each one is a separate MapKit
    /// search, and MapKit limits how many searches an app can run per minute.
    public static let maxSelection = 4

    /// A selection in chip order. Empty means "All".
    public static func ordered(_ selection: Set<CuisineFilter>) -> [CuisineFilter] {
        let picked = specific.filter { selection.contains($0) }
        return picked.isEmpty ? [.all] : picked
    }

    /// "BBQ, Mexican", "BBQ, Mexican + 1 more", or "all".
    public static func summary(of selection: Set<CuisineFilter>) -> String {
        let picked = specific.filter { selection.contains($0) }.map(\.label)
        switch picked.count {
        case 0: return "all"
        case 1, 2: return picked.joined(separator: ", ")
        default: return "\(picked[0]), \(picked[1]) + \(picked.count - 2) more"
        }
    }

    /// The phrase sent to MapKit search.
    public var query: String {
        switch self {
        case .all: return "restaurant"
        case .cafe: return "cafe"
        case .bbq: return "barbecue restaurant"
        default: return "\(label) restaurant"
        }
    }

    // MARK: Matching places we already have

    /// Words that suggest a place serves this cuisine, checked against its
    /// category and name. Used to filter saved places, which have no cuisine data.
    var keywords: [String] {
        switch self {
        case .all: return []
        case .mexican: return ["mexican", "taco", "tacos", "taqueria", "burrito", "cantina", "tex-mex", "chipotle", "qdoba", "moe's"]
        case .japanese: return ["japanese", "sushi", "ramen", "hibachi", "izakaya", "teriyaki", "udon"]
        case .bbq: return ["bbq", "barbecue", "smokehouse", "bar-b-q"]
        case .italian: return ["italian", "trattoria", "ristorante", "osteria", "pasta", "olive garden", "fazoli's"]
        case .pizza: return ["pizza", "pizzeria"]
        case .burgers: return ["burger", "burgers"]
        case .chinese: return ["chinese", "wok", "dumpling", "szechuan", "sichuan", "hunan", "panda express"]
        case .thai: return ["thai"]
        case .indian: return ["indian", "curry", "tandoor", "tandoori", "masala", "biryani"]
        case .cafe: return ["cafe", "café", "coffee", "espresso", "bakery", "starbucks"]
        }
    }

    /// True when a place looks like this cuisine. `.all` matches everything.
    public func matches(name: String, category: String) -> Bool {
        if self == .all { return true }
        let haystack = " " + (category + " " + name).lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'") + " "
        if category.caseInsensitiveCompare(label) == .orderedSame { return true }
        return keywords.contains { word in
            // Whole words only: "thai" matches "Thai House", not "Thailand".
            let pattern = "(^|[^a-z])" + NSRegularExpression.escapedPattern(for: word) + "([^a-z]|$)"
            return haystack.range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// True when a place matches any cuisine in the selection (empty = all).
    public static func matches(_ selection: Set<CuisineFilter>, name: String, category: String) -> Bool {
        selection.isEmpty || selection.contains { $0.matches(name: name, category: category) }
    }
}
