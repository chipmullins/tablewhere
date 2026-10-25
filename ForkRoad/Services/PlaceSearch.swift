import Foundation
import MapKit
import PickerCore

/// Anything that can find restaurants. The app uses MapKit; previews and
/// tests can swap in a fake.
protocol PlaceSearching {
    func search(near center: CLLocationCoordinate2D,
                radiusMeters: Double,
                cuisine: CuisineFilter) async throws -> [Place]
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
                cuisine: CuisineFilter) async throws -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = cuisine.query
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
                guard distance <= radiusMeters else { return nil }
                return Place(
                    name: name,
                    category: Self.categoryName(for: item, cuisine: cuisine),
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
    private static func categoryName(for item: MKMapItem, cuisine: CuisineFilter) -> String {
        if cuisine != .all { return cuisine.label }
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
