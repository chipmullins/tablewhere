import SwiftUI
import CoreLocation
import PickerCore

enum AppTab: String, Hashable {
    case discover, spin, lists, group
}

enum SpinSource: String, CaseIterable, Identifiable {
    case nearby = "Nearby"
    /// A wheel you build yourself: any places, plus anything you type.
    case picked = "Pick"
    case favorites = "Favorites"
    case interested = "Interested"
    var id: Self { self }

    /// What the picker shows. (The raw values stay as they were.)
    var label: String {
        switch self {
        case .nearby: return "Nearby"
        case .picked: return "Custom"
        case .favorites: return "Favorites"
        case .interested: return "To try"
        }
    }

    /// The saved list this source spins from, if it's one.
    var savedList: SavedList? {
        switch self {
        case .nearby, .picked: return nil
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
    /// Opens where you left off (iOS often closes the app in the background).
    var selectedTab: AppTab = AppTab(rawValue: UserDefaults.standard.string(forKey: "lastTab") ?? "") ?? .discover {
        didSet { UserDefaults.standard.set(selectedTab.rawValue, forKey: "lastTab") }
    }
    var spinSource: SpinSource = .nearby
    /// Spin → Eat in: spin your home meals instead of restaurants.
    var eatIn = false
    /// Set to open Lists on the Home list (Spin → Eat in → Edit).
    var showHomeList = false
    /// Set by "Spin for it" / "Spin my favorites": Spin starts as soon as it opens.
    var pendingSpin = false
    /// Places you passed on with "Not tonight" (left out of spins for a few hours,
    /// unlike Blacklist, which is forever).
    private(set) var skippedForNow: [String: Date] = [:]
    var skippedForNowIDs: Set<String> {
        Set(skippedForNow.filter { -$0.value.timeIntervalSinceNow < 6 * 3600 }.keys)
    }
    func skipForNow(_ place: Place) { skippedForNow[place.id] = Date() }
    func unskipForNow(_ place: Place) { skippedForNow[place.id] = nil }

    /// The hand-picked wheel (Spin → Pick). Saved on this device.
    var pickedWheel: [Place] = AppModel.savedWheel {
        didSet {
            if let data = try? JSONEncoder().encode(pickedWheel) {
                UserDefaults.standard.set(data, forKey: "spin.pickedWheel")
            }
        }
    }
    private static var savedWheel: [Place] {
        guard let data = UserDefaults.standard.data(forKey: "spin.pickedWheel") else { return [] }
        return (try? JSONDecoder().decode([Place].self, from: data)) ?? []
    }
    /// Most places on a hand-picked wheel.
    static let maxPicked = 20

    func togglePicked(_ place: Place) {
        if let index = pickedWheel.firstIndex(where: { $0.id == place.id }) {
            pickedWheel.remove(at: index)
        } else if pickedWheel.count < Self.maxPicked {
            pickedWheel.append(place)
        }
    }

    /// Adds anything you type ("Mom's", "Leftovers") as a wheel slot.
    /// It has no real location, so it's placed at your search center.
    func addTypedPick(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, pickedWheel.count < Self.maxPicked,
              !pickedWheel.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        pickedWheel.append(Place(id: "typed|" + UUID().uuidString, name: trimmed, category: "Your pick",
                                 latitude: center.latitude, longitude: center.longitude, distanceMeters: 0))
    }

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
    /// "No coffee & sweets" (on by default). Shared with the iMessage extension.
    var excludeCoffeeAndSweets: Bool = Preferences.excludeCoffeeAndSweets {
        didSet { Preferences.excludeCoffeeAndSweets = excludeCoffeeAndSweets }
    }

    private(set) var places: [Place] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// True after the first search finishes (so empty states don't flash at launch).
    private(set) var hasSearched = false
    /// A group to open (from a notification or link); GroupHomeView pushes it.
    var pendingGroupSessionID: String?
    /// A place to open on Discover (from the widget).
    var pendingPlace: Place?
    /// A place to start an "I'll pick" group plan with (Spin → "Make it a group
    /// plan"); GroupHomeView opens New group plan with it.
    var pendingPlanPlace: Place?

    /// Opens Group and starts a plan for this place.
    func startPlan(with place: Place) {
        pendingPlanPlace = place
        selectedTab = .group
    }

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
    /// True once we know where to look: your location, or a place you picked.
    /// Until then nothing is searched (no quietly showing Lexington, KY).
    var hasLocation: Bool { chosenLocation != nil || location.coordinate != nil }

    var center: CLLocationCoordinate2D {
        chosenLocation?.coordinate ?? location.coordinate ?? LocationManager.fallback
    }

    var isUsingCurrentLocation: Bool { chosenLocation == nil }

    /// "Lexington, KY", "Chevy Chase", or "Near you".
    var locationName: String { chosenLocation?.name ?? location.displayName }

    /// `persist: false` searches there now but opens on your location next
    /// time (used for map taps, unless location is off and there's no other way).
    func choose(_ place: ChosenLocation, remember: Bool = true, persist: Bool = true) {
        chosenLocation = place
        ChosenLocation.saved = persist ? place : nil
        if remember { ChosenLocation.remember(place) }
        scheduleSearch()
    }

    /// Searches around a spot picked on the map (a tap, or "Search this area").
    /// It's named "Pinned spot" at once, then after the neighborhood or street
    /// once Apple Maps looks it up. Map spots don't fill up the Recent list.
    func searchHere(_ coordinate: CLLocationCoordinate2D) {
        let pin = ChosenLocation(name: "Pinned spot", subtitle: "From the map",
                                 latitude: coordinate.latitude, longitude: coordinate.longitude)
        // A map tap is for right now: next launch opens on your location again.
        // (With location off, keep it, so there's still somewhere to look.)
        let persist = location.isDenied || location.coordinate == nil
        choose(pin, remember: false, persist: persist)
        Task {
            guard let name = await Self.spotName(for: coordinate),
                  chosenLocation?.id == pin.id else { return }  // moved again meanwhile
            var named = pin
            named.name = name
            chosenLocation = named
            if persist { ChosenLocation.saved = named }
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
            excludeFastFood: excludeFastFood,
            excludeCoffeeAndSweets: excludeCoffeeAndSweets
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
        showCachedResults()
        // The first search runs once there's somewhere to look (a GPS fix or
        // a chosen place); the location callback schedules it.
        if hasLocation { scheduleSearch() }
    }

    /// Opens on the last results right away when they fit where and how
    /// we're about to search, so launch never shows an empty screen while
    /// Apple Maps answers. The fresh search replaces them quietly.
    private func showCachedResults() {
        guard places.isEmpty, hasLocation,
              let area = SharedCache.loadSearchArea(),
              area.radiusMiles == radiusMiles, area.cuisines == cuisines.filter({ $0 != .all }), area.diet == diet else { return }
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let there = CLLocation(latitude: area.latitude, longitude: area.longitude)
        guard here.distance(from: there) < 500 else { return }
        let cached = SharedCache.loadNearby()
        guard !cached.isEmpty else { return }
        places = cached
        hasSearched = true
        Task { await refreshCurrentCity() }
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

    /// Pull to refresh / Try again: skip saved results and search for real.
    func refresh() async {
        await SearchCache.shared.clear()
        await search()
    }

    func search() async {
        guard hasLocation else {
            places = []
            hasSearched = true
            return
        }
        searchGeneration += 1
        let generation = searchGeneration
        isLoading = true
        errorMessage = nil
        // What this search is for (the filters can change while it runs).
        let area = searchArea
        do {
            let results = try await searchService.search(
                near: area.center,
                radiusMeters: area.radiusMiles * Place.metersPerMile,
                cuisines: area.cuisines,
                diet: area.diet
            )
            guard generation == searchGeneration else { return }  // a newer search took over
            places = results
            Task { await refreshCurrentCity() }
            SharedCache.saveNearby(results)  // lets the iMessage extension offer these
            SharedCache.saveSearchArea(area)
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
