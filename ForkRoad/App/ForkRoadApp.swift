import SwiftUI
import SwiftData

@main
struct ForkRoadApp: App {
    @State private var model = AppModel()

    init() {
        // Group voting needs Firebase; everything else works without it.
        FirebaseSetup.configureIfPossible()
        Theme.applyUIKitAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .font(Theme.body(16))
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.saffron)
        }
        .modelContainer(ForkRoadStore.container)
    }
}
