import SwiftUI
import CoreLocation
import PickerCore

enum AppTab: Hashable {
    case discover, spin, lists
}

enum SpinSource: String, CaseIterable, Identifiable {
    case nearby = "Everywhere nearby"
    case interested = "Interested list"
    var id: Self { self }
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
    var cuisine: CuisineFilter = .all {
        didSet { if cuisine != oldValue { scheduleSearch() } }
    }

    private(set) var places: [Place] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let location = LocationManager()

    @ObservationIgnored private let searchService: PlaceSearching
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Increments per search so only the newest one updates the UI.
    @ObservationIgnored private var searchGeneration = 0

    init(searchService: PlaceSearching = MapKitPlaceSearch()) {
        self.searchService = searchService
        location.onUpdate = { [weak self] in self?.scheduleSearch() }
    }

    var center: CLLocationCoordinate2D { location.coordinate ?? LocationManager.fallback }
    var radiusMeters: Double { radiusMiles * Place.metersPerMile }

    var radiusLabel: String {
        radiusMiles.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(radiusMiles)) mi"
            : String(format: "%.1f mi", radiusMiles)
    }

    /// Call once when the app appears. The first search runs when a location
    /// arrives (or we learn there won't be one), so fallback results don't flash first.
    func start() {
        location.start()
        if location.isDenied { scheduleSearch() }
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
                cuisine: cuisine
            )
            guard generation == searchGeneration else { return }  // a newer search took over
            places = results
        } catch {
            guard generation == searchGeneration else { return }
            if !(error is CancellationError) {
                errorMessage = "Couldn’t load restaurants. Check your connection and try again."
            }
        }
        isLoading = false
    }
}
