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

    /// The phrase sent to MapKit search.
    public var query: String {
        switch self {
        case .all: return "restaurant"
        case .cafe: return "cafe"
        case .bbq: return "barbecue restaurant"
        default: return "\(label) restaurant"
        }
    }
}
