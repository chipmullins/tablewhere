import Foundation
import SwiftData
import PickerCore

/// A meal you make at home ("Chicken tacos"), for Spin → Eat in.
/// Deliberately tiny: a name, and optionally a note or a link to the recipe.
/// Every property has a default, as CloudKit requires.
@Model
final class HomeRecipe {
    /// Stable ID (used for "Not tonight" and the reel).
    var recipeID: String = UUID().uuidString
    var name: String = ""
    /// "Mom's", "double the garlic", "needs the slow cooker".
    var note: String = ""
    /// Where the recipe lives (a website, a video), if anywhere.
    var link: URL?
    var createdAt: Date = Date()

    init(name: String, note: String = "", link: URL? = nil) {
        recipeID = UUID().uuidString
        self.name = name
        self.note = note
        self.link = link
        createdAt = .now
    }

    /// The reel spins Places, so a recipe rides along as one: its ID starts
    /// with "recipe|" (never a real place), and the link travels as the website.
    var asSpinItem: Place {
        Place(id: Self.idPrefix + recipeID, name: name, category: "Home",
              latitude: 0, longitude: 0, distanceMeters: 0, websiteURL: link)
    }

    static let idPrefix = "recipe|"

    static func isRecipe(_ place: Place) -> Bool { place.id.hasPrefix(idPrefix) }

    /// "nytimes.com/…" or a bare "allrecipes.com" typed without https://.
    static func link(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host else { return nil }
        // "allrecipes.com", not "hello" or "hello."
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, !parts.contains(where: \.isEmpty) else { return nil }
        return url
    }
}
