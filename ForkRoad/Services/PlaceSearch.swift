import Foundation
import MapKit
import PickerCore

/// Anything that can find restaurants. The app uses MapKit; previews and
/// tests can swap in a fake.
protocol PlaceSearching: Sendable {
    func search(near center: CLLocationCoordinate2D,
                radiusMeters: Double,
                cuisine: CuisineFilter,
                diet: DietFilter) async throws -> [Place]

    /// Free-text search ("Sora Ramen", "tacos", "brunch") around a point.
    func search(text: String,
                near center: CLLocationCoordinate2D,
                radiusMeters: Double) async throws -> [Place]
}

extension PlaceSearching {
    func search(near center: CLLocationCoordinate2D,
                radiusMeters: Double,
                cuisine: CuisineFilter) async throws -> [Place] {
        try await search(near: center, radiusMeters: radiusMeters, cuisine: cuisine, diet: .none)
    }

    /// Searches several cuisines at once and merges the results (nearest first).
    /// An empty selection means "All". The diet applies to every cuisine.
    func search(near center: CLLocationCoordinate2D,
                radiusMeters: Double,
                cuisines: Set<CuisineFilter>,
                diet: DietFilter = .none) async throws -> [Place] {
        let list = CuisineFilter.ordered(cuisines)
        if list.count == 1 {
            return try await search(near: center, radiusMeters: radiusMeters, cuisine: list[0], diet: diet)
        }
        let batches = try await withThrowingTaskGroup(of: (Int, [Place]?).self) { group in
            for (index, cuisine) in list.enumerated() {
                group.addTask {
                    // One cuisine failing shouldn't sink the others.
                    let places = try? await self.search(near: center, radiusMeters: radiusMeters,
                                                        cuisine: cuisine, diet: diet)
                    return (index, places)
                }
            }
            var results = [(Int, [Place]?)]()
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        if batches.allSatisfy({ $0 == nil }) { throw URLError(.cannotLoadFromNetwork) }

        var seen = Set<String>()
        return batches
            .compactMap { $0 }
            .flatMap { $0 }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }
}

/// Searches Apple Maps data with MapKit. Free, with no API key.
///
/// Known limits of MapKit search:
/// - It returns a limited number of results per request (roughly a couple dozen),
///   which is fine for picking dinner but not a full directory.
/// - It doesn't provide opening hours, photos, or menus. We link to the
///   restaurant's website for menus and hours instead.
struct MapKitPlaceSearch: PlaceSearching {

    func search(near center: CLLocationCoordinate2D,
                radiusMeters: Double,
                cuisine: CuisineFilter,
                diet: DietFilter) async throws -> [Place] {
        try await run(query: diet.query(for: cuisine), center: center, radiusMeters: radiusMeters,
                      cuisine: cuisine, diet: diet, trimToRadius: true)
    }

    func search(text: String,
                near center: CLLocationCoordinate2D,
                radiusMeters: Double) async throws -> [Place] {
        // A name search shouldn't miss a place just outside the circle,
        // so results aren't trimmed to the radius (MapKit still favors the area).
        try await run(query: text, center: center, radiusMeters: radiusMeters,
                      cuisine: .all, diet: .none, trimToRadius: false)
    }

    private func run(query: String,
                     center: CLLocationCoordinate2D,
                     radiusMeters: Double,
                     cuisine: CuisineFilter,
                     diet: DietFilter,
                     trimToRadius: Bool) async throws -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket
        ])
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )

        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)

        var seen = Set<String>()
        return response.mapItems
            .compactMap { item -> Place? in
                guard let name = item.name, let location = item.placemark.location else { return nil }
                let distance = origin.distance(from: location)
                // The search region is a square; trim results to the circle the user chose.
                if trimToRadius && distance > radiusMeters { return nil }
                return Place(
                    name: name,
                    category: Self.categoryName(for: item, cuisine: cuisine, diet: diet),
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    distanceMeters: distance,
                    phoneNumber: item.phoneNumber,
                    websiteURL: item.url,
                    address: item.placemark.title
                )
            }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    /// MapKit has no cuisine data, so when a cuisine chip is active we use its
    /// name; otherwise we fall back to MapKit's broad category.
    private static func categoryName(for item: MKMapItem, cuisine: CuisineFilter, diet: DietFilter) -> String {
        if cuisine != .all { return cuisine.label }
        if diet != .none { return diet.label }
        switch item.pointOfInterestCategory {
        case .cafe?: return "Café"
        case .bakery?: return "Bakery"
        case .brewery?: return "Brewery"
        case .winery?: return "Winery"
        case .foodMarket?: return "Market"
        default: return "Restaurant"
        }
    }
}
