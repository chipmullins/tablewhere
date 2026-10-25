import SwiftUI
import SwiftData

@main
struct ForkRoadApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.saffron)
        }
        .modelContainer(for: [
            SavedPlace.self,
            BlockedPlace.self,
            BlockedCategory.self,
            SpinRecord.self
        ])
    }
}
