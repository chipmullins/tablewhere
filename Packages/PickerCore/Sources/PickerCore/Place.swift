import Foundation
import CoreLocation

/// A restaurant the user can pick. Built from MapKit results in the app,
/// but kept free of MapKit types so it is easy to test and to share.
public struct Place: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let category: String
    public let latitude: Double
    public let longitude: Double
    /// Straight-line distance from the search center, in meters.
    public let distanceMeters: Double
    public let phoneNumber: String?
    public let websiteURL: URL?
    public let address: String?

    public init(
        id: String? = nil,
        name: String,
        category: String,
        latitude: Double,
        longitude: Double,
        distanceMeters: Double,
        phoneNumber: String? = nil,
        websiteURL: URL? = nil,
        address: String? = nil
    ) {
        self.id = id ?? Place.makeID(name: name, latitude: latitude, longitude: longitude)
        self.name = name
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.distanceMeters = distanceMeters
        self.phoneNumber = phoneNumber
        self.websiteURL = websiteURL
        self.address = address
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public var distanceMiles: Double { distanceMeters / Place.metersPerMile }

    /// "0.4 mi" style label.
    public var distanceLabel: String {
        String(format: distanceMiles < 10 ? "%.1f mi" : "%.0f mi", distanceMiles)
    }

    public static let metersPerMile = 1609.344

    /// A stable ID from name + rounded coordinates, so the same restaurant
    /// keeps the same ID across searches (used by saved and blocked lists).
    public static func makeID(name: String, latitude: Double, longitude: Double) -> String {
        let lat = (latitude * 10_000).rounded() / 10_000
        let lon = (longitude * 10_000).rounded() / 10_000
        return "\(name.lowercased())|\(lat)|\(lon)"
    }
}
