import Foundation

/// Dietary filter. Unlike cuisines (which you can mix), a diet narrows every
/// search: Vegan + Mexican searches for "vegan Mexican restaurant".
public enum DietFilter: String, CaseIterable, Identifiable, Sendable, Codable {
    case none, vegetarian, vegan, glutenFree

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return "Any diet"
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .glutenFree: return "Gluten-free"
        }
    }

    /// Words put in front of the search phrase.
    public var searchPrefix: String {
        switch self {
        case .none: return ""
        case .vegetarian: return "vegetarian "
        case .vegan: return "vegan "
        case .glutenFree: return "gluten free "
        }
    }

    /// The full MapKit search phrase for a cuisine with this diet.
    public func query(for cuisine: CuisineFilter) -> String {
        searchPrefix + cuisine.query
    }

    /// The diets shown as chips (everything except "Any diet").
    public static var specific: [DietFilter] { allCases.filter { $0 != .none } }
}
