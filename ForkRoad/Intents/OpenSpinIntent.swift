import AppIntents
import Foundation

/// "Spin in Tablespin": opens the app on the Spin tab and spins right away.
/// This is the "Spin" App Shortcut, so it's also what people pick for the
/// Action Button (Settings → Action Button → Shortcut → ForkRoad → Spin).
/// The app reads `pendingDeepLink` on launch/foreground, switches tabs, and clears it.
struct OpenSpinIntent: AppIntent {
    static var title: LocalizedStringResource = "Spin for a place to eat"
    static var description = IntentDescription(
        "Opens Tablespin on the Spin tab and spins for a place to eat.",
        categoryName: "Picking"
    )
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        SpinLink.post()
        return .result()
    }
}
