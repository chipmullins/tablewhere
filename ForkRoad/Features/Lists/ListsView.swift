import SwiftUI
import SwiftData
import PickerCore

/// The Interested list and the Blocked list.
struct ListsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case interested = "Interested"
        case blocked = "Blocked"
        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query(sort: \BlockedPlace.blockedAt, order: .reverse) private var blockedPlaces: [BlockedPlace]
    @Query(sort: \BlockedCategory.blockedAt, order: .reverse) private var blockedCategories: [BlockedCategory]

    @State private var tab: Tab = .interested

    var body: some View {
        List {
            Section {
                Picker("List", selection: $tab) {
                    ForEach(Tab.allCases) { Text(label(for: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            switch tab {
            case .interested: interestedSection
            case .blocked: blockedSections
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.night)
        .navigationTitle("Your lists")
        .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
    }

    private func label(for tab: Tab) -> String {
        switch tab {
        case .interested: return "Interested · \(saved.count)"
        case .blocked: return "Blocked · \(blockedPlaces.count + blockedCategories.count)"
        }
    }

    @ViewBuilder
    private var interestedSection: some View {
        if saved.isEmpty {
            Text("Tap the heart on any restaurant to save it here.")
                .foregroundStyle(Theme.muted)
                .listRowBackground(Color.clear)
        } else {
            Section {
                Button {
                    model.spinSource = .interested
                    model.selectedTab = .spin
                } label: {
                    Label("Pick from these", systemImage: "dice")
                        .font(Theme.display(17))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .listRowBackground(Theme.saffron)
            }

            Section {
                ForEach(saved) { item in
                    NavigationLink(value: item.asPlace(from: model.center)) {
                        HStack(spacing: 12) {
                            MonogramTile(name: item.name, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(Theme.body(16, .semibold))
                                Text(item.category).font(Theme.body(13)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
                .onDelete { offsets in offsets.map { saved[$0] }.forEach { context.delete($0) } }
                .listRowBackground(Theme.surface)
            }
        }
    }

    @ViewBuilder
    private var blockedSections: some View {
        if blockedPlaces.isEmpty && blockedCategories.isEmpty {
            Text("Nothing blocked. Blocked places and categories never come up in Discover or spins.")
                .foregroundStyle(Theme.muted)
                .listRowBackground(Color.clear)
        }
        if !blockedCategories.isEmpty {
            Section("Categories") {
                ForEach(blockedCategories) { Text($0.name) }
                    .onDelete { offsets in offsets.map { blockedCategories[$0] }.forEach { context.delete($0) } }
                    .listRowBackground(Theme.surface)
            }
        }
        if !blockedPlaces.isEmpty {
            Section("Places") {
                ForEach(blockedPlaces) { Text($0.name) }
                    .onDelete { offsets in offsets.map { blockedPlaces[$0] }.forEach { context.delete($0) } }
                    .listRowBackground(Theme.surface)
            }
        }
        if !blockedPlaces.isEmpty || !blockedCategories.isEmpty {
            Text("Swipe left to unblock.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.muted)
                .listRowBackground(Color.clear)
        }
    }
}
