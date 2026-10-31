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
    @Query private var areas: [SavedArea]

    @State private var tab: Tab = .favorites
    @State private var showAddPlace = false

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddPlace = true } label: {
                    Label("Add a restaurant", systemImage: "plus")
                }
                .accessibilityHint("Add a place that isn’t on Apple Maps")
            }
        }
        .sheet(isPresented: $showAddPlace) {
            CustomPlaceForm(startingList: tab == .favorites ? .favorites : .interested) {
                if tab == .blocked { tab = .interested }
            }
        }
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
        case .favorites: return "Favorites \(items(in: .favorites).filtered(by: model.listCity, near: model.center, areas: areas).count)"
        case .interested: return "Interested \(items(in: .interested).filtered(by: model.listCity, near: model.center, areas: areas).count)"
        case .blocked: return "Blacklisted \(blockedPlaces.count + blockedCategories.count)"
        }
    }

    // MARK: Favorites / Interested

    @ViewBuilder
    private func savedSections(_ list: SavedList) -> some View {
        let all = items(in: list)
        let metros = all.metros
        let rows = all.filtered(by: model.listCity, near: model.center, areas: areas)
        let areaName = areaLabel(metros)

        Section {
            CityMenu(metros: metros)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        if all.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(list == .favorites
                     ? "Tap the heart on a restaurant you love to add it here."
                     : "Tap the bookmark on a restaurant you want to try to save it here.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.muted)
                addPlaceLink
            }
            .listRowBackground(Color.clear)
        } else if rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No \(list == .favorites ? "favorites" : "saved places") \(areaName.map { "in \($0)" } ?? "around here") yet.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 18) {
                    Button("Show all areas") { model.listCity = .all }
                        .font(Theme.body(15, .semibold))
                        .foregroundStyle(Theme.accentText)
                    addPlaceLink
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                Button {
                    model.spinSource = SpinSource(list)
                    model.selectedTab = .spin
                } label: {
                    Label(spinTitle(list, area: areaName), systemImage: "dice")
                        .font(Theme.display(17))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .listRowBackground(Theme.saffron)
            }

            if model.listCity == .all {
                // All areas: one section per metro area.
                ForEach(metros) { metro in
                    Section {
                        savedRows(metro.items, list: list)
                    } header: {
                        Text("\(metro.label) · \(metro.items.count)")
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
                     ? "Tried one and loved it? Swipe right to move it to Favorites. Swipe left to skip a place in spins or remove it. Missing a place? Tap + to add it."
                     : "Swipe left to skip a favorite in spins (it stays on your list) or remove it. Swipe right to move it back to Interested.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var addPlaceLink: some View {
        Button { showAddPlace = true } label: {
            Label("Add one yourself", systemImage: "plus.circle")
                .font(Theme.body(15, .semibold))
                .foregroundStyle(Theme.accentText)
        }
        .buttonStyle(.plain)
    }

    private func spinTitle(_ list: SavedList, area: String?) -> String {
        let base = list == .favorites ? "Spin my favorites" : "Spin something new"
        guard let area, let short = area.split(separator: ",").first else { return base }
        return "\(base) in \(short)"
    }

    /// Name of the metro the filter points at, or nil for "All areas" / nowhere.
    private func areaLabel(_ metros: [Metro]) -> String? {
        switch model.listCity {
        case .all: return nil
        case .metro(let name): return metros.first { $0.name == name }?.label ?? name
        case .area(let name): return name
        case .here: return metros.first { $0.contains(model.center) }?.label ?? model.currentCity
        }
    }

    @ViewBuilder
    private func savedRows(_ rows: [SavedPlace], list: SavedList) -> some View {
        ForEach(rows) { item in
            NavigationLink(value: item.asPlace(from: model.center)) {
                HStack(spacing: 12) {
                    MonogramTile(name: item.name, category: item.category, size: 44)
                        .opacity(item.skipInSpins ? 0.45 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(Theme.body(16, .semibold))
                        Text(rowDetail(item))
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.muted)
                        if !item.note.isEmpty {
                            Label(item.note, systemImage: "note.text")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if item.skipInSpins {
                        Image(systemName: "pause.circle")
                            .foregroundStyle(Theme.muted)
                            .accessibilityLabel("Left out of spins")
                    }
                }
            }
            .swipeActions(edge: .trailing) {
                Button(item.isCustom ? "Delete" : "Remove", systemImage: "trash", role: .destructive) { context.delete(item) }
                Button(item.skipInSpins ? "Spin it" : "Skip",
                       systemImage: item.skipInSpins ? "dice" : "pause.circle") {
                    item.skipInSpins.toggle()
                }
                .tint(Theme.trackFill)
            }
            .contextMenu {
                Button(item.skipInSpins ? "Include in spins" : "Leave out of spins",
                       systemImage: item.skipInSpins ? "dice" : "pause.circle") {
                    item.skipInSpins.toggle()
                }
            }
            .swipeActions(edge: .leading) {
                if list == .interested {
                    Button("Loved it", systemImage: "heart.fill") { actions.move(item, to: .favorites) }
                        .tint(Theme.saffron)
                } else {
                    Button("Try later", systemImage: "bookmark.fill") { actions.move(item, to: .interested) }
                        .tint(Theme.trackFill)
                }
            }
        }
    }

    /// "BBQ · added by you · no address · left out of spins"
    private func rowDetail(_ item: SavedPlace) -> String {
        var parts = [item.category]
        if item.isCustom { parts.append(item.hasExactLocation ? "added by you" : "added by you · no address") }
        if item.skipInSpins { parts.append("left out of spins") }
        return parts.joined(separator: " · ")
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
