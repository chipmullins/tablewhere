import AppIntents
import Foundation

/// "Spin in ForkRoad": opens the app on the Spin tab.
/// The app reads `pendingDeepLink` on launch/foreground, switches tabs, and clears it.
struct OpenSpinIntent: AppIntent {
    static var title: LocalizedStringResource = "Spin in ForkRoad"
    static var description = IntentDescription("Opens ForkRoad on the Spin tab.")
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { DeepLink.post("spin") }
        return .result()
    }
}
