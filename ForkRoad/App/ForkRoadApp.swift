import SwiftUI
import SwiftData

@main
struct ForkRoadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance: AppearanceChoice = .system
    @AppStorage("didOnboard") private var didOnboard = false

    init() {
        // Group voting needs Firebase; everything else works without it.
        FirebaseSetup.configureIfPossible()
        Theme.applyUIKitAppearance()
        // Group plans show "Leave by" on the Lock Screen (app-only; see LeaveBy.activityUpdate).
        LiveActivities.install()
        // "On my way" keeps your arrival time fresh while you drive (1.1).
        OnMyWayLive.install()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .font(Theme.body(16))
                .environment(model)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accentText)
                .fullScreenCover(isPresented: Binding(get: { !didOnboard }, set: { _ in })) {
                    OnboardingView { didOnboard = true }
                        .environment(model)
                        .preferredColorScheme(appearance.colorScheme)
                        .tint(Theme.accentText)
                        .interactiveDismissDisabled()
                }
        }
        .modelContainer(ForkRoadStore.container)
    }
}
