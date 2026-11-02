import SwiftUI
import CoreLocation
import PickerCore

/// What a row in the group place picker shows on the right.
enum PlacePickerAccessory {
    /// Multi-select (starting a vote): a checkmark circle.
    case check(isOn: Bool)
    /// Add one at a time (suggesting a place): a plus, or a spinner while it's added.
    case add(isBusy: Bool)
}

/// Where a place picker looks when you're not searching by name.
enum PickerSource: String, CaseIterable, Identifiable {
    case nearby, favorites, interested
    var id: Self { self }
    var title: String {
        switch self {
        case .nearby: return "Nearby"
        case .favorites: return "Favorites"
        case .interested: return "To try"
        }
    }
}

/// The filters a group picker searches with. Starts from Discover's, but
/// changing them here doesn't change Discover.
struct PlacePickerFilters: Equatable {
    var cuisines: Set<CuisineFilter> = []
    var diet: DietFilter = .none
    var radiusMiles: Double = 2

    init(cuisines: Set<CuisineFilter> = [], diet: DietFilter = .none, radiusMiles: Double = 2) {
        self.cuisines = cuisines
        self.diet = diet
        self.radiusMiles = radiusMiles
    }

    init(_ area: SearchArea) {
        self.init(cuisines: area.cuisines, diet: area.diet, radiusMiles: area.radiusMiles)
    }
}

/// Picking places for a group vote, with the same filters as Discover:
/// radius, cuisines (up to 4), diet, no fast food, plus a name search.
///
/// Its body is list sections, so put it inside a `List` or `Form`, and pass
/// the text from the list's `.searchable` field as `query`. Used by the app
/// (new group, suggest a place) and the iMessage extension.
struct GroupPlacePicker: View {
    let query: String
    /// Where to search. Nil means no live search (only `startingNearby` is
    /// shown) until you pick an area.
    let center: CLLocationCoordinate2D?
    /// What `center` is called ("Near you", "Lexington, KY"), shown on the
    /// "Searching near" row.
    var centerName: String = "Your search area"
    let favorites: [Place]
    let interested: [Place]
    /// Filters to start with, and results that already match them (skips a search).
    let startingFilters: PlacePickerFilters
    let startingNearby: [Place]
    /// Blacklist and "No fast food".
    let rules: Randomizer.Rules
    /// Places already in the vote; hidden.
    var excludedIDs: Set<String> = []
    /// The group's scrambled blacklists (and its session ID to scramble with):
    /// places anyone in the group blacklisted are hidden.
    var groupBlockedHashes: Set<String> = []
    var sessionID: String?
    var search: PlaceSearching = MapKitPlaceSearch()
    let accessory: (Place) -> PlacePickerAccessory
    var isDisabled: (Place) -> Bool = { _ in false }
    /// Told when you pick a different area (nil: back to `center`).
    var onAreaChange: (PickerArea?) -> Void = { _ in }
    let onTap: (Place) -> Void

    @State private var filters: PlacePickerFilters?
    /// Nearby, Favorites, or To try. Remembered between pickers.
    @AppStorage("placePickerSource") private var source: PickerSource = .nearby
    @State private var nearby: [Place] = []
    @State private var isLoadingNearby = false
    @State private var nearbyError: String?
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var searchedQuery: String?
    /// The filters and spot `nearby` was loaded with (so clearing a search doesn't search again).
    @State private var loadedKey: NearbyKey?
    /// A spot picked for this picker only (Discover and Spin keep theirs).
    @State private var pickedArea: PickerArea?
    @State private var showAreaSheet = false
    @State private var showAreaMap = false

    /// What a nearby search depends on.
    private struct NearbyKey: Equatable {
        var filters: PlacePickerFilters
        var area: PickerArea?
    }
    private var nearbyKey: NearbyKey { NearbyKey(filters: current, area: pickedArea) }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var isTextSearch: Bool { trimmedQuery.count >= 2 }
    private var current: PlacePickerFilters { filters ?? startingFilters }
    /// The picked spot, else the usual center.
    private var searchCenter: CLLocationCoordinate2D? { pickedArea?.coordinate ?? center }

    private var filtersBinding: Binding<PlacePickerFilters> {
        Binding(get: { current }, set: { filters = $0 })
    }

    /// `chosen`: your saved lists or a name search, where a coffee shop is
    /// there on purpose (No coffee & sweets only trims nearby results).
    private func available(_ places: [Place], chosen: Bool = false) -> [Place] {
        var rules = self.rules
        if chosen { rules.excludeCoffeeAndSweets = false }
        return Randomizer.eligible(places, rules: rules).filter { place in
            if excludedIDs.contains(place.id) { return false }
            if let sessionID, !groupBlockedHashes.isEmpty,
               groupBlockedHashes.contains(GroupBlacklist.hash(placeID: place.id, sessionID: sessionID)) { return false }
            return true
        }
    }

    var body: some View {
        if isTextSearch {
            // Searching: results first (the filters don't apply to a name
            // search, so they step aside until the search is cleared).
            Section {
                if isSearching && results.isEmpty {
                    skeletonRows
                } else if !isSearching && searchedQuery == trimmedQuery && available(results, chosen: true).isEmpty {
                    statusRow("No restaurants found for “\(trimmedQuery)”. Try a broader word like “pizza.”")
                }
                ForEach(available(results, chosen: true)) { place in
                    Button { onTap(place) } label: { row(place) }
                        .disabled(isDisabled(place))
                }
            } header: {
                Text("Results")
            }
            .listRowBackground(Theme.surface)
            .task(id: TextSearchKey(query: trimmedQuery, area: pickedArea)) { await runTextSearch() }
        } else {
            // Pick where to look: nearby (with filters), or one of your lists.
            Section {
                Picker("Show", selection: $source) {
                    ForEach(PickerSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(Haptic.tick, trigger: source)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            switch source {
            case .nearby:
                nearbySections
            case .favorites:
                let favs = available(favorites, chosen: true)
                section("Your favorites", favs)
                if favs.isEmpty {
                    statusRow(favorites.isEmpty
                              ? "Tap the heart on a restaurant to see it here."
                              : "None of your favorites can be added here.")
                }
            case .interested:
                let wants = available(interested, chosen: true)
                section("To try", wants)
                if wants.isEmpty {
                    statusRow(interested.isEmpty
                              ? "Curious about a place? Bookmark it and it shows up here."
                              : "None of your places to try can be added here.")
                }
            }
        }
    }

    /// Nearby: where to look, the filters, then the results.
    @ViewBuilder
    private var nearbySections: some View {
        Section {
            areaRow
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                // On one row, not the Section (a List can repeat Section modifiers per row).
                .task(id: nearbyKey) { await loadNearby() }
                .onChange(of: pickedArea) { onAreaChange(pickedArea) }
                .sheet(isPresented: $showAreaSheet) {
                    PickerAreaSheet(defaultCenter: center, defaultName: centerName,
                                    current: pickedArea) { pickedArea = $0 }
                }
                .fullScreenCover(isPresented: $showAreaMap) {
                    PickerMapView(start: searchCenter) { pickedArea = $0 }
                }
            RadiusSlider(miles: filtersBinding.radiusMiles)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            CuisineChips(selection: filtersBinding.cuisines, diet: filtersBinding.diet)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
        } header: {
            Text("Filters")
        } footer: {
            if !groupBlockedHashes.isEmpty {
                Text("Places anyone in the group has blacklisted are hidden.")
            }
        }

        let near = available(nearby)
        section(nearbyTitle, near)
        if isLoadingNearby && near.isEmpty {
            Section(nearbyTitle) { skeletonRows }
                .listRowBackground(Theme.surface)
        } else if let nearbyError {
            statusRow(nearbyError)
        } else if near.isEmpty {
            statusRow(searchCenter == nil
                      ? "Choose where to look above, or search by name."
                      : "Nothing matches. Try a bigger radius, fewer filters, or search above.")
        }
    }

    private var nearbyTitle: String {
        let radius = RadiusSlider.label(current.radiusMiles)
        if let pickedArea {
            let what = current.cuisines.isEmpty ? "Places" : CuisineFilter.summary(of: current.cuisines)
            return "\(what) within \(radius) of \(pickedArea.name)"
        }
        let what = current.cuisines.isEmpty ? "Nearby" : CuisineFilter.summary(of: current.cuisines)
        return "\(what) within \(radius)"
    }

    /// "Searching near …" (opens the area sheet), with quick chips for the
    /// map and for going back to the usual area.
    private var areaRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showAreaSheet = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: pickedArea == nil ? "location.fill" : "mappin")
                        .foregroundStyle(Theme.accentText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Searching near").font(Theme.body(12)).foregroundStyle(Theme.muted)
                        Text(pickedArea?.name ?? (searchCenter == nil ? "Choose a place" : centerName))
                            .font(Theme.body(16, .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(Theme.body(12, .bold)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Search for a city, neighborhood, or address")

            HStack(spacing: 8) {
                if pickedArea != nil && center != nil {
                    areaChip("Reset area", icon: "arrow.uturn.backward") { pickedArea = nil }
                }
                areaChip("Choose on map", icon: "map.fill") { showAreaMap = true }
                Spacer(minLength: 0)
            }
        }
    }

    private func areaChip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(Theme.body(14, .semibold))
                .foregroundStyle(Theme.accentText)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Theme.accentSoft, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func section(_ title: String, _ places: [Place]) -> some View {
        if !places.isEmpty {
            Section(title) {
                ForEach(places) { place in
                    Button { onTap(place) } label: { row(place) }
                        .disabled(isDisabled(place))
                }
            }
            .listRowBackground(Theme.surface)
        }
    }

    private func row(_ place: Place) -> some View {
        let kind = accessory(place)
        return HStack(spacing: 12) {
            MonogramTile(name: place.name, category: place.category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(Theme.text)
                Text("\(place.category) · \(place.distanceLabel)")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            switch kind {
            case .check(let isOn):
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(Theme.body(22))
                    .foregroundStyle(isOn ? Theme.accentText : Theme.muted.opacity(0.5))
                    .accessibilityHidden(true)
            case .add(let isBusy):
                if isBusy { ProgressView() }
                else { Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentText) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected(place) ? .isSelected : [])
        // Per row, from its own state, so only the tapped row plays: a tick
        // when it's checked or unchecked, a commit when it starts being added.
        .sensoryFeedback(Haptic.tick, trigger: isSelected(place))
        .sensoryFeedback(trigger: isAdding(kind)) { old, new in !old && new ? Haptic.commit : nil }
    }

    private func isAdding(_ accessory: PlacePickerAccessory) -> Bool {
        if case .add(isBusy: true) = accessory { return true }
        return false
    }

    private func isSelected(_ place: Place) -> Bool {
        if case .check(isOn: true) = accessory(place) { return true }
        return false
    }

    private func statusRow(_ text: String) -> some View {
        Text(text).font(Theme.body(14)).foregroundStyle(Theme.muted)
            .listRowBackground(Color.clear)
    }

    /// Three placeholder rows while results load (VoiceOver hears one "Loading").
    private var skeletonRows: some View {
        ForEach(0..<3, id: \.self) { index in
            ListRowPlaceholder()
                .loadingSkeleton(announces: index == 0)
        }
    }

    // MARK: Searching

    private struct TextSearchKey: Equatable {
        var query: String
        var area: PickerArea?
    }

    private func loadNearby() async {
        let key = nearbyKey
        let wanted = key.filters
        if loadedKey == key && !nearby.isEmpty { return }
        // Moved somewhere else: don't leave the old area's places up while searching.
        if loadedKey?.area != key.area {
            nearby = []
            isLoadingNearby = true  // skeletons, not "Nothing matches", while it waits
        }
        // Discover already searched with these filters, in the same place: reuse its results.
        if key.area == nil && wanted == startingFilters && !startingNearby.isEmpty {
            nearby = startingNearby
            nearbyError = nil
            loadedKey = key
            isLoadingNearby = false
            return
        }
        guard let center = searchCenter else {
            nearby = startingNearby.filter {
                CuisineFilter.matches(wanted.cuisines, name: $0.name, category: $0.category)
                    && $0.distanceMeters <= wanted.radiusMiles * Place.metersPerMile
            }
            loadedKey = key
            isLoadingNearby = false
            return
        }
        // Wait until the slider or chips settle (MapKit limits searches per minute).
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        isLoadingNearby = true
        nearbyError = nil
        defer { isLoadingNearby = false }
        do {
            let found = try await search.search(near: center,
                                                radiusMeters: wanted.radiusMiles * Place.metersPerMile,
                                                cuisines: wanted.cuisines,
                                                diet: wanted.diet)
            guard !Task.isCancelled else { return }
            nearby = found
            loadedKey = key
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            nearbyError = "Couldn’t load nearby places. Check your connection."
        }
    }

    private func runTextSearch() async {
        let text = trimmedQuery
        guard text.count >= 2, let center = searchCenter else {
            results = []
            searchedQuery = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        // A name search looks at least 15 miles out, like Discover's.
        let radius = max(current.radiusMiles, 15) * Place.metersPerMile
        if let found = try? await search.search(text: text, near: center, radiusMeters: radius),
           !Task.isCancelled {
            results = found
            searchedQuery = text
        }
    }
}
