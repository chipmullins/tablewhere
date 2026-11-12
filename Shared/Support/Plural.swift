import Foundation

/// "1 place", "3 places". English only, like the rest of the app's wording.
func plural(_ count: Int, _ singular: String, _ pluralForm: String? = nil) -> String {
    "\(count) \(count == 1 ? singular : (pluralForm ?? singular + "s"))"
}
