import Foundation
import CoreLocation

/// Turns coordinates into a city name like "Lexington, KY".
///
/// Apple limits how often an app can look up addresses, so lookups run one
/// at a time and results are cached by rounded coordinate (about 1 km).
@MainActor
enum CityResolver {
    private static let geocoder = CLGeocoder()
    private static var cache: [String: String] = [:]
    private static var queue: Task<Void, Never>?

    static func city(for coordinate: CLLocationCoordinate2D) async -> String? {
        let key = String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
        if let cached = cache[key] { return cached }

        // Wait for any lookup already in flight (CLGeocoder handles one at a time).
        let previous = queue
        let task = Task<String?, Never> {
            await previous?.value
            if let cached = cache[key] { return cached }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let mark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
            let city = mark.locality ?? mark.subAdministrativeArea ?? mark.name
            let name = [city, mark.administrativeArea].compactMap { $0 }.joined(separator: ", ")
            guard !name.isEmpty else { return nil }
            cache[key] = name
            return name
        }
        queue = Task { _ = await task.value }
        return await task.value
    }
}
