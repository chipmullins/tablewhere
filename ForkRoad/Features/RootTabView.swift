import SwiftUI
import SwiftData
import PickerCore

struct RootTabView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedTab) {
            NavigationStack { DiscoverView() }
                .tabItem { Label("Discover", systemImage: "safari") }
                .tag(AppTab.discover)

            NavigationStack { SpinView() }
                .tabItem { Label("Spin", systemImage: "dice") }
                .tag(AppTab.spin)

            NavigationStack { ListsView() }
                .tabItem { Label("Lists", systemImage: "heart") }
                .tag(AppTab.lists)

            GroupHomeView()  // owns its NavigationStack so it can push new sessions
                .tabItem { Label("Group", systemImage: "person.2") }
                .tag(AppTab.group)

            NavigationStack { TripsView() }
                .tabItem { Label("Trips", systemImage: "globe.americas") }
                .tag(AppTab.trips)
        }
        .toolbarBackground(Theme.night, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task { model.start() }
        // Keep the iMessage extension's copies of Favorites and Interested current.
        .onChange(of: saved.map { "\($0.placeID)|\($0.listRaw)" }, initial: true) {
            SharedCache.saveFavorites(saved.filter { $0.list == .favorites }.map { $0.asPlace(from: model.center) })
            SharedCache.saveInterested(saved.filter { $0.list == .interested }.map { $0.asPlace(from: model.center) })
        }
    }
}
