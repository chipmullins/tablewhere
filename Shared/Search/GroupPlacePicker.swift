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
    /// Where to search. Nil means no live search (only `startingNearby` is shown).
    let center: CLLocationCoordinate2D?
    let favorites: [Place]
    let interested: [Place]
    /// Filters to start with, and results that already match them (skips a search).
    let startingFilters: PlacePickerFilters
    let startingNearby: [Place]
    /// Blacklist and "No fast food".
    let rules: Randomizer.Rules
    /// Places already in the vote; hidden.
    var excludedIDs: Set<String> = []
    var search: PlaceSearching = MapKitPlaceSearch()
    let accessory: (Place) -> PlacePickerAccessory
    var isDisabled: (Place) -> Bool = { _ in false }
    let onTap: (Place) -> Void

    @State private var filters: PlacePickerFilters?
    @State private var nearby: [Place] = []
    @State private var isLoadingNearby = false
    @State private var nearbyError: String?
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var searchedQuery: String?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var isTextSearch: Bool { trimmedQuery.count >= 2 }
    private var current: PlacePickerFilters { filters ?? startingFilters }

    private var filtersBinding: Binding<PlacePickerFilters> {
        Binding(get: { current }, set: { filters = $0 })
    }

    private func available(_ places: [Place]) -> [Place] {
        Randomizer.eligible(places, rules: rules).filter { !excludedIDs.contains($0.id) }
    }

    /// Saved places have no cuisine data, so the chips match on name and category.
    private func savedMatching(_ places: [Place]) -> [Place] {
        available(places).filter { CuisineFilter.matches(current.cuisines, name: $0.name, category: $0.category) }
    }

    var body: some View {
        Section {
            RadiusSlider(miles: filtersBinding.radiusMiles)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            CuisineChips(selection: filtersBinding.cuisines, diet: filtersBinding.diet)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
        } header: {
            Text(isTextSearch ? "Filters (apply when the search is cleared)" : "Filters")
        }
        .task(id: current) { await loadNearby() }
        .task(id: trimmedQuery) { await runTextSearch() }

        if isTextSearch {
            if isSearching && results.isEmpty {
                statusRow("Searching…", showsSpinner: true)
            } else if !isSearching && searchedQuery == trimmedQuery && available(results).isEmpty {
                statusRow("No restaurants found for “\(trimmedQuery)”. Try a broader word like “pizza.”")
            }
            section("Results", available(results))
        } else {
            let favs = savedMatching(favorites)
            let wants = savedMatching(interested)
            let savedIDs = Set((favorites + interested).map(\.id))
            let near = available(nearby).filter { !savedIDs.contains($0.id) }
            section("Your favorites", favs)
            section("Want to try", wants)
            section(nearbyTitle, near)
            if isLoadingNearby && near.isEmpty {
                statusRow("Looking nearby…", showsSpinner: true)
            } else if let nearbyError {
                statusRow(nearbyError)
            } else if favs.isEmpty && wants.isEmpty && near.isEmpty {
                statusRow(center == nil
                          ? "Open ForkRoad and look around nearby first, or search above."
                          : "Nothing matches. Try a bigger radius, fewer filters, or search above.")
            }
        }
    }

    private var nearbyTitle: String {
        let what = current.cuisines.isEmpty ? "Nearby" : CuisineFilter.summary(of: current.cuisines)
        return "\(what) within \(RadiusSlider.label(current.radiusMiles))"
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
        HStack(spacing: 12) {
            MonogramTile(name: place.name, category: place.category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(Theme.text)
                Text("\(place.category) · \(place.distanceLabel)")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            switch accessory(place) {
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
    }

    private func isSelected(_ place: Place) -> Bool {
        if case .check(isOn: true) = accessory(place) { return true }
        return false
    }

    private func statusRow(_ text: String, showsSpinner: Bool = false) -> some View {
        HStack(spacing: 10) {
            if showsSpinner { ProgressView().tint(Theme.muted) }
            Text(text).font(Theme.body(14)).foregroundStyle(Theme.muted)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: Searching

    private func loadNearby() async {
        let wanted = current
        // Discover already searched with these filters: reuse its results.
        if wanted == startingFilters && !startingNearby.isEmpty {
            nearby = startingNearby
            nearbyError = nil
            return
        }
        guard let center else {
            nearby = startingNearby.filter {
                CuisineFilter.matches(wanted.cuisines, name: $0.name, category: $0.category)
                    && $0.distanceMeters <= wanted.radiusMiles * Place.metersPerMile
            }
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
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            nearbyError = "Couldn’t load nearby places. Check your connection."
        }
    }

    private func runTextSearch() async {
        let text = trimmedQuery
        guard text.count >= 2, let center else {
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
