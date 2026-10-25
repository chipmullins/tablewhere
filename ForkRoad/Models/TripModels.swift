import Foundation
import CoreLocation
import SwiftData
import PickerCore

/// A trip to another city, with the restaurants saved for it.
/// Relationships are optional and every property has a default, as CloudKit requires.
@Model
final class Trip {
    var name: String = ""
    var cityName: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TripPlace.trip)
    var places: [TripPlace]? = []

    init(name: String, cityName: String, coordinate: CLLocationCoordinate2D) {
        self.name = name
        self.cityName = cityName
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        createdAt = .now
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var sortedPlaces: [TripPlace] {
        (places ?? []).sorted { $0.addedAt < $1.addedAt }
    }

    func contains(_ place: Place) -> Bool {
        (places ?? []).contains { $0.placeID == place.id }
    }
}

@Model
final class TripPlace {
    var placeID: String = ""
    var name: String = ""
    var category: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var phoneNumber: String?
    var websiteURL: URL?
    var address: String?
    var addedAt: Date = Date()
    var trip: Trip?

    init(place: Place) {
        placeID = place.id
        name = place.name
        category = place.category
        latitude = place.latitude
        longitude = place.longitude
        phoneNumber = place.phoneNumber
        websiteURL = place.websiteURL
        address = place.address
        addedAt = .now
    }

    func asPlace(from center: CLLocationCoordinate2D) -> Place {
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let there = CLLocation(latitude: latitude, longitude: longitude)
        return Place(id: placeID, name: name, category: category,
                     latitude: latitude, longitude: longitude,
                     distanceMeters: here.distance(from: there),
                     phoneNumber: phoneNumber, websiteURL: websiteURL, address: address)
    }
}
