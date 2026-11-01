import AppIntents
import Foundation

// Compiled by the app AND the widget extension (project.yml lists this file
// in ForkRoadWidgets' sources), so it may only use Foundation, AppIntents,
// and Shared/Support (SharedDefaults). No app-only types such as DeepLink.

/// "Open the Spin tab and spin": the link the Control Center button and the
/// "Spin" App Shortcut (Action Button, Siri) leave for the app.
enum SpinLink {
    /// Same as forkroad://spin?go=1. RootTabView's `handle(_:)` switches to
    /// Spin and sets `model.pendingSpin`, which makes the Spin tab spin.
    static let autoSpin = "spin?go=1"

    /// Leaves the link for the app, which reads it when it becomes active.
    /// Uses DeepLink's storage key and notification (ForkRoad/App/AppDelegate.swift),
    /// spelled out because DeepLink isn't in the widget extension.
    @MainActor
    static func post() {
        SharedDefaults.store.set(autoSpin, forKey: "pendingDeepLink")
        // Only reaches the app when this runs in the app's process (it's a
        // no-op in the extension); otherwise the app picks the link up on activation.
        NotificationCenter.default.post(name: Notification.Name("ForkRoadDeepLink"), object: nil)
    }
}

/// The Control Center / Lock Screen "Spin" button (iOS 18). Opens ForkRoad and spins.
/// Hidden from Shortcuts: the "Spin" App Shortcut (OpenSpinIntent) does the same there.
struct SpinNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Spin for a place to eat"
    static var description = IntentDescription("Opens ForkRoad on the Spin tab and spins.")
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        SpinLink.post()
        return .result()
    }
}
