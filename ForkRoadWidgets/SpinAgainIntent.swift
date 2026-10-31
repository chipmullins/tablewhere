import AppIntents
import Foundation

/// The widget's "Spin again" button. Picks a new seed so the widget shows a different
/// place; WidgetKit reloads the widget's timeline after an interactive intent finishes.
struct SpinAgainIntent: AppIntent {
    static var title: LocalizedStringResource = "Spin again"
    static var description = IntentDescription("Shows a different place on the Your Pick widget.")
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        let now = Date()
        let currentID = WidgetPick.pick(at: now)?.place.id
        var newSeed = UInt64.random(in: .min ... .max)
        // Try a few seeds so the button visibly changes the pick when there's more than one place.
        for _ in 0..<12 {
            guard let id = WidgetPick.pick(at: now, seed: newSeed)?.place.id, id == currentID else { break }
            newSeed = UInt64.random(in: .min ... .max)
        }
        WidgetPick.seed = newSeed
        return .result()
    }
}
