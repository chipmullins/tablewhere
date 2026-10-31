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

    /// Remembered between launches (also settable in Settings).
    var radiusMiles: Double = AppModel.savedRadius {
        didSet {
            guard radiusMiles != oldValue else { return }
            UserDefaults.standard.set(radiusMiles, forKey: "radiusMiles")
            scheduleSearch()
        }
    }
    private static var savedRadius: Double {
        let value = UserDefaults.standard.double(forKey: "radiusMiles")
        return value >= 0.5 ? value : 2
    }
    /// Vegetarian / vegan / gluten-free. Remembered between launches.
    var diet: DietFilter = DietFilter(rawValue: UserDefaults.standard.string(forKey: "diet") ?? "") ?? .none {
        didSet {
            guard diet != oldValue else { return }
            UserDefaults.standard.set(diet.rawValue, forKey: "diet")
            scheduleSearch()
        }
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
    /// True after the first search finishes (so empty states don't flash at launch).
    private(set) var hasSearched = false
    /// A group to open (from a notification or link); GroupHomeView pushes it.
    var pendingGroupSessionID: String?

    /// The city you're searching in ("Lexington, KY"), looked up from `center`.
    private(set) var currentCity: String?
    /// Which metro area the Favorites/Interested lists (and spins from them) show.
    var listCity: CityFilter = .here

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

    func choose(_ place: ChosenLocation, remember: Bool = true) {
        chosenLocation = place
        ChosenLocation.saved = place
        if remember { ChosenLocation.remember(place) }
        scheduleSearch()
    }

    /// Searches around a spot picked on the map (a tap, or "Search this area").
    /// It's named "Pinned spot" at once, then after the neighborhood or street
    /// once Apple Maps looks it up. Map spots don't fill up the Recent list.
    func searchHere(_ coordinate: CLLocationCoordinate2D) {
        let pin = ChosenLocation(name: "Pinned spot", subtitle: "From the map",
                                 latitude: coordinate.latitude, longitude: coordinate.longitude)
        choose(pin, remember: false)
        Task {
            guard let name = await Self.spotName(for: coordinate),
                  chosenLocation?.id == pin.id else { return }  // moved again meanwhile
            var named = pin
            named.name = name
            chosenLocation = named
            ChosenLocation.saved = named
        }
    }

    /// "Chevy Chase", "S Limestone", or the city, for a map spot.
    private static func spotName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        if let area = mark.subLocality { return area }
        if let street = mark.thoroughfare { return "Near \(street)" }
        return mark.locality
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

    var radiusLabel: String { RadiusSlider.label(radiusMiles) }

    /// Call once when the app appears. The first search runs when a location
    /// arrives (or we learn there won't be one), so fallback results don't flash first.
    func start() {
        // Before onboarding, don't trigger the permission prompt; onboarding asks
        // with context (or the user picks a city instead).
        let onboarded = UserDefaults.standard.bool(forKey: "didOnboard")
        if onboarded && chosenLocation == nil { location.start() }
        if !onboarded || location.isDenied || chosenLocation != nil
            || location.authorization == .authorizedWhenInUse || location.authorization == .authorizedAlways {
            scheduleSearch()
        }
    }

    /// Runs a filtered nearby search without touching Discover's results
    /// (used by the group place pickers, which have their own filters).
    var placeSearch: PlaceSearching { searchService }

    /// Discover's current filters, as a starting point for the group pickers.
    var searchArea: SearchArea {
        SearchArea(center: center, radiusMiles: radiusMiles, cuisines: cuisines, diet: diet)
    }

    /// Searches restaurants by name or craving around the current area
    /// (at least 15 miles, so a name search finds places just outside your radius).
    func searchRestaurants(_ text: String) async throws -> [Place] {
        try await searchService.search(text: text, near: center,
                                       radiusMeters: max(radiusMeters, 15 * Place.metersPerMile))
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
                cuisines: cuisines,
                diet: diet
            )
            guard generation == searchGeneration else { return }  // a newer search took over
            places = results
            Task { await refreshCurrentCity() }
            SharedCache.saveNearby(results)  // lets the iMessage extension offer these
            SharedCache.saveSearchArea(SearchArea(center: center, radiusMiles: radiusMiles,
                                                  cuisines: cuisines, diet: diet))
        } catch {
            guard generation == searchGeneration else { return }
            if !(error is CancellationError) {
                errorMessage = "Couldn’t load restaurants. Check your connection and try again."
            }
        }
        isLoading = false
        hasSearched = true
    }
}
