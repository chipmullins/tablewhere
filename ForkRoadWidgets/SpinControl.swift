import SwiftUI
import WidgetKit
import AppIntents

/// iOS 18 Control Center / Lock Screen / Action Button control: opens ForkRoad
/// on the Spin tab and spins. The intent lives in ForkRoad/Intents/SpinNowIntent.swift,
/// compiled into both the app and this extension so the app can run it when it opens.
@available(iOS 18.0, *)
struct SpinControl: ControlWidget {
    static let kind = "com.chipmullins.forkroad.widgets.spin"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: SpinNowIntent()) {
                Label("Spin", systemImage: "sparkles")
            }
        }
        .displayName("Spin")
        .description("Opens Tablespin and spins for a place to eat.")
    }
}
