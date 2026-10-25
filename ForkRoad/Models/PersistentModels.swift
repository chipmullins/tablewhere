import Foundation
import CoreLocation
import SwiftData
import PickerCore

// Data saved on the device with SwiftData.
//
// No @Attribute(.unique) on purpose: CloudKit sync (planned) doesn't support
// unique constraints, so duplicates are prevented in code instead (see ListActions).
// Every property also has a default value, which CloudKit requires.

/// A restaurant on the user's Interested list.
@Model
final class SavedPlace {
    var placeID: String = ""
    var name: String = ""
    var category: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var phoneNumber: String?
    var websiteURL: URL?
    var savedAt: Date = Date()

    init(place: Place) {
        placeID = place.id
        name = place.name
        category = place.category
        latitude = place.latitude
        longitude = place.longitude
        phoneNumber = place.phoneNumber
        websiteURL = place.websiteURL
        savedAt = .now
    }

    /// Rebuilds a Place, measuring distance from the current search center.
    func asPlace(from center: CLLocationCoordinate2D) -> Place {
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let there = CLLocation(latitude: latitude, longitude: longitude)
        return Place(id: placeID, name: name, category: category,
                     latitude: latitude, longitude: longitude,
                     distanceMeters: here.distance(from: there),
                     phoneNumber: phoneNumber, websiteURL: websiteURL)
    }
}

/// One restaurant the user never wants suggested.
@Model
final class BlockedPlace {
    var placeID: String = ""
    var name: String = ""
    var blockedAt: Date = Date()

    init(place: Place) {
        placeID = place.id
        name = place.name
        blockedAt = .now
    }
}

/// A whole category the user never wants suggested ("Seafood").
@Model
final class BlockedCategory {
    var name: String = ""
    var blockedAt: Date = Date()

    init(name: String) {
        self.name = name
        blockedAt = .now
    }
}

/// A spin result, used to avoid repeats.
@Model
final class SpinRecord {
    var placeID: String = ""
    var spunAt: Date = Date()

    init(placeID: String) {
        self.placeID = placeID
        spunAt = .now
    }
}
