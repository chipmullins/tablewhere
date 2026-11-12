import Foundation
import CoreLocation
import Observation

/// Wraps CLLocationManager: asks for permission, gets one location fix,
/// and looks up a friendly place name ("Lexington, KY").
@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    /// Used when location is denied or not available yet (Lexington, KY).
    static let fallback = CLLocationCoordinate2D(latitude: 38.0406, longitude: -84.5037)

    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var placeName: String?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    /// Called whenever there's a new location, or when we know there won't be one.
    @ObservationIgnored var onUpdate: (() -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = manager.authorizationStatus
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// Label for the header: the real place name, or the fallback city.
    var displayName: String {
        if let placeName { return placeName }
        return coordinate == nil ? "Choose a location" : "Near you"
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            // A recent last-known fix gets the first search going at once;
            // the fresh fix below refines it.
            if coordinate == nil, let last = manager.location,
               -last.timestamp.timeIntervalSinceNow < 15 * 60 {
                coordinate = last.coordinate
                onUpdate?()
            }
            manager.requestLocation()
        default:
            break
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            } else if self.isDenied {
                self.onUpdate?()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            // Barely moved since the last-known fix: keep its results (no second search).
            let moved = self.coordinate.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location) > 200
            } ?? true
            self.coordinate = location.coordinate
            if moved { self.onUpdate?() }
            await self.lookUpPlaceName(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.onUpdate?() }
    }

    private func lookUpPlaceName(for location: CLLocation) async {
        guard let mark = try? await geocoder.reverseGeocodeLocation(location).first else { return }
        let parts = [mark.locality, mark.administrativeArea].compactMap { $0 }
        if !parts.isEmpty { placeName = parts.joined(separator: ", ") }
    }
}
