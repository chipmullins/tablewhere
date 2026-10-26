import SwiftUI
import SwiftData
import PickerCore

/// Favorites (places you love), Interested (places to try), and Blacklisted.
struct ListsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case favorites = "Favorites"
        case interested = "Interested"
        case blocked = "Blacklisted"
        var id: Self { self }

        var savedList: SavedList? {
            switch self {
            case .favorites: return .favorites
            case .interested: return .interested
            case .blocked: return nil
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query(sort: \BlockedPlace.blockedAt, order: .reverse) private var blockedPlaces: [BlockedPlace]
    @Query(sort: \BlockedCategory.blockedAt, order: .reverse) private var blockedCategories: [BlockedCategory]

    @State private var tab: Tab = .favorites

    private var actions: ListActions { ListActions(context: context) }

    private func items(in list: SavedList) -> [SavedPlace] {
        saved.filter { $0.list == list }
    }

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

            if let list = tab.savedList {
                savedSections(list)
            } else {
                blockedSections
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.night)
        .navigationTitle("Your lists")
        .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
        .animation(.snappy, value: saved.map(\.listRaw))
        // Fill in cities for places saved before cities existed (one at a time).
        .task {
            for item in saved where item.city.isEmpty {
                await ListActions.fillInCity(item)
            }
        }
    }

    private func label(for tab: Tab) -> String {
        switch tab {
        case .favorites: return "Favorites \(items(in: .favorites).inCity(model.effectiveListCity).count)"
        case .interested: return "Interested \(items(in: .interested).inCity(model.effectiveListCity).count)"
        case .blocked: return "Blacklisted \(blockedPlaces.count + blockedCategories.count)"
        }
    }

    // MARK: Favorites / Interested

    @ViewBuilder
    private func savedSections(_ list: SavedList) -> some View {
        let all = items(in: list)
        let city = model.effectiveListCity
        let rows = all.inCity(city)

        if !all.isEmpty {
            Section {
                CityMenu(cityCounts: all.cityCounts)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }

        if all.isEmpty {
            Text(list == .favorites
                 ? "Tap the heart on a restaurant you love to add it here."
                 : "Tap the bookmark on a restaurant you want to try to save it here.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.muted)
                .listRowBackground(Color.clear)
        } else if rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No \(list == .favorites ? "favorites" : "saved places") in \(city ?? "this city") yet.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.muted)
                Button("Show all cities") { model.listCity = .all }
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.saffron)
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                Button {
                    model.spinSource = SpinSource(list)
                    model.selectedTab = .spin
                } label: {
                    Label(spinTitle(list, city: city), systemImage: "dice")
                        .font(Theme.display(17))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .listRowBackground(Theme.saffron)
            }

            if city == nil {
                // All cities: one section per city, like a drop-down per city.
                ForEach(rows.groupedByCity, id: \.city) { group in
                    Section {
                        savedRows(group.items, list: list)
                    } header: {
                        Text("\(group.city) · \(group.items.count)")
                    }
                    .listRowBackground(Theme.surface)
                }
            } else {
                Section {
                    savedRows(rows, list: list)
                }
                .listRowBackground(Theme.surface)
            }

            Section {} footer: {
                Text(list == .interested
                     ? "Tried one and loved it? Swipe right to move it to Favorites."
                     : "Swipe right to move a place back to Interested, or left to remove it.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func spinTitle(_ list: SavedList, city: String?) -> String {
        let base = list == .favorites ? "Spin my favorites" : "Spin something new"
        guard let city, let short = city.split(separator: ",").first else { return base }
        return "\(base) in \(short)"
    }

    @ViewBuilder
    private func savedRows(_ rows: [SavedPlace], list: SavedList) -> some View {
        ForEach(rows) { item in
            NavigationLink(value: item.asPlace(from: model.center)) {
                HStack(spacing: 12) {
                    MonogramTile(name: item.name, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(Theme.body(16, .semibold))
                        Text(item.category).font(Theme.body(13)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .swipeActions(edge: .trailing) {
                Button("Remove", systemImage: "trash", role: .destructive) { context.delete(item) }
            }
            .swipeActions(edge: .leading) {
                if list == .interested {
                    Button("Loved it", systemImage: "heart.fill") { actions.move(item, to: .favorites) }
                        .tint(Theme.saffron)
                } else {
                    Button("Try later", systemImage: "bookmark.fill") { actions.move(item, to: .interested) }
                        .tint(Color(hex: 0x5C5A66))
                }
            }
        }
    }

    // MARK: Blacklisted

    @ViewBuilder
    private var blockedSections: some View {
        if blockedPlaces.isEmpty && blockedCategories.isEmpty {
            Text("Nothing blacklisted. Blacklisted places and categories never come up in Discover or spins.")
                .font(Theme.body(15))
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
            Text("Swipe left to remove from the blacklist.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.muted)
                .listRowBackground(Color.clear)
        }
    }
}
