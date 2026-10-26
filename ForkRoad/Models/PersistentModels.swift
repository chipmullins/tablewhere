import Foundation
import CoreLocation
import SwiftData
import PickerCore

// Data saved on the device with SwiftData.
//
// No @Attribute(.unique) on purpose: CloudKit sync (planned) doesn't support
// unique constraints, so duplicates are prevented in code instead (see ListActions).
// Every property also has a default value, which CloudKit requires.

/// Which list a saved restaurant is on.
enum SavedList: String, CaseIterable, Identifiable {
    /// Places you love and go back to.
    case favorites
    /// Places you want to try.
    case interested

    var id: Self { self }

    var title: String {
        switch self {
        case .favorites: return "Favorites"
        case .interested: return "Interested"
        }
    }

    var systemImage: String {
        switch self {
        case .favorites: return "heart"
        case .interested: return "bookmark"
        }
    }
}

/// A restaurant on the user's Favorites or Interested list.
@Model
final class SavedPlace {
    /// Raw value of `SavedList`. Older saves (before Favorites existed) default to Interested.
    var listRaw: String = SavedList.interested.rawValue
    var placeID: String = ""
    var name: String = ""
    var category: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var phoneNumber: String?
    var websiteURL: URL?
    var savedAt: Date = Date()

    var list: SavedList {
        get { SavedList(rawValue: listRaw) ?? .interested }
        set { listRaw = newValue.rawValue }
    }

    init(place: Place, list: SavedList) {
        listRaw = list.rawValue
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
