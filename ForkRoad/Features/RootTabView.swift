import SwiftUI

struct RootTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedTab) {
            NavigationStack { DiscoverView() }
                .tabItem { Label("Discover", systemImage: "safari") }
                .tag(AppTab.discover)

            NavigationStack { SpinView() }
                .tabItem { Label("Spin", systemImage: "shuffle") }
                .tag(AppTab.spin)

            NavigationStack { ListsView() }
                .tabItem { Label("Lists", systemImage: "heart") }
                .tag(AppTab.lists)
        }
        .toolbarBackground(Theme.night, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task { model.start() }
    }
}
