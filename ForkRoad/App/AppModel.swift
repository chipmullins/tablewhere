import SwiftUI
import CoreLocation
import PickerCore

enum AppTab: Hashable {
    case discover, spin, lists, group, trips
}

enum SpinSource: String, CaseIterable, Identifiable {
    case nearby = "Nearby"
    case favorites = "Favorites"
    case interested = "Interested"
    var id: Self { self }

    /// The saved list this source spins from, if it's one.
    var savedList: SavedList? {
        switch self {
        case .nearby: return nil
        case .favorites: return .favorites
        case .interested: return .interested
        }
    }

    init(_ list: SavedList) {
        self = list == .favorites ? .favorites : .interested
    }
}

/// App-wide state shared by every tab: where we're searching, how far,
/// which cuisine, and the latest results.
@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .discover
    var spinSource: SpinSource = .nearby

    var radiusMiles: Double = 2 {
        didSet { if radiusMiles != oldValue { scheduleSearch() } }
    }
    /// Selected cuisines. Empty means "All".
    var cuisines: Set<CuisineFilter> = [] {
        didSet { if cuisines != oldValue { scheduleSearch() } }
    }
    /// "No fast food" toggle. Saved, and shared with the iMessage extension.
    var excludeFastFood: Bool = Preferences.excludeFastFood {
        didSet { Preferences.excludeFastFood = excludeFastFood }
    }

    private(set) var places: [Place] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// The city you're searching in ("Lexington, KY"), looked up from `center`.
    private(set) var currentCity: String?
    /// Which city the Favorites/Interested lists (and spins from them) show.
    var listCity: CityFilter = .here

    /// The city name the saved lists should be filtered to, or nil for all cities.
    var effectiveListCity: String? {
        switch listCity {
        case .here: return currentCity
        case .all: return nil
        case .city(let name): return name
        }
    }

    let location = LocationManager()

    @ObservationIgnored private let searchService: PlaceSearching
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Increments per search so only the newest one updates the UI.
    @ObservationIgnored private var searchGeneration = 0

    init(searchService: PlaceSearching = MapKitPlaceSearch()) {
        self.searchService = searchService
        location.onUpdate = { [weak self] in
            // GPS updates don't matter while a chosen place is in use.
            guard let self, self.chosenLocation == nil else { return }
            self.scheduleSearch()
        }
    }

    /// A place the user picked instead of their current location. Saved between launches.
    private(set) var chosenLocation: ChosenLocation? = ChosenLocation.saved

    /// Where searches are centered: the chosen place, else GPS, else Lexington.
    var center: CLLocationCoordinate2D {
        chosenLocation?.coordinate ?? location.coordinate ?? LocationManager.fallback
    }

    var isUsingCurrentLocation: Bool { chosenLocation == nil }

    /// "Lexington, KY", "Chevy Chase", or "Near you".
    var locationName: String { chosenLocation?.name ?? location.displayName }

    func choose(_ place: ChosenLocation) {
        chosenLocation = place
        ChosenLocation.saved = place
        ChosenLocation.remember(place)
        scheduleSearch()
    }

    func useCurrentLocation() {
        chosenLocation = nil
        ChosenLocation.saved = nil
        location.start()
        scheduleSearch()
    }

    /// The block/fast-food rules every screen applies.
    func rules(blockedPlaces: [BlockedPlace], blockedCategories: [BlockedCategory],
               recent: Set<String> = [], maxDistance: Double? = nil) -> Randomizer.Rules {
        Randomizer.Rules(
            blockedPlaceIDs: Set(blockedPlaces.map(\.placeID)),
            blockedCategories: Set(blockedCategories.map(\.name)),
            recentPlaceIDs: recent,
            maxDistanceMeters: maxDistance,
            excludeFastFood: excludeFastFood
        )
    }
    var radiusMeters: Double { radiusMiles * Place.metersPerMile }

    /// "BBQ, Mexican" or "all" — used in labels like "Spin from 12 BBQ, Mexican places".
    var cuisineSummary: String { CuisineFilter.summary(of: cuisines) }

    var radiusLabel: String {
        radiusMiles.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(radiusMiles)) mi"
            : String(format: "%.1f mi", radiusMiles)
    }

    /// Call once when the app appears. The first search runs when a location
    /// arrives (or we learn there won't be one), so fallback results don't flash first.
    func start() {
        location.start()
        if location.isDenied || chosenLocation != nil { scheduleSearch() }
    }

    private func refreshCurrentCity() async {
        if let city = await CityResolver.city(for: center) { currentCity = city }
    }

    /// Debounced search, so dragging the radius slider doesn't fire a search per pixel.
    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.search()
        }
    }

    func search() async {
        searchGeneration += 1
        let generation = searchGeneration
        isLoading = true
        errorMessage = nil
        do {
            let results = try await searchService.search(
                near: center,
                radiusMeters: radiusMeters,
                cuisines: cuisines
            )
            guard generation == searchGeneration else { return }  // a newer search took over
            places = results
            Task { await refreshCurrentCity() }
            SharedCache.saveNearby(results)  // lets the iMessage extension offer these
        } catch {
            guard generation == searchGeneration else { return }
            if !(error is CancellationError) {
                errorMessage = "Couldn’t load restaurants. Check your connection and try again."
            }
        }
        isLoading = false
    }
}
