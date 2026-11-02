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
        case .interested: return "To try"
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
    /// "Lexington, KY". Filled in by looking up the coordinates after saving;
    /// empty until then (and for saves made before cities existed).
    var city: String = ""
    /// Still on the list, but never picked by a spin (e.g. a favorite you're tired of for now).
    var skipInSpins: Bool = false
    /// Your own note, like "get the spicy miso" or "cash only".
    var note: String = ""
    var placeID: String = ""
    var name: String = ""
    var category: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var phoneNumber: String?
    var websiteURL: URL?
    var savedAt: Date = Date()
    /// A restaurant you added yourself (not from Apple Maps).
    var isCustom: Bool = false
    /// Street address, if you gave one (your own places only).
    var address: String = ""
    /// False when you added your own place without an address: it sits at the
    /// middle of the area you chose, so there are no directions to it and it
    /// isn't offered to groups (friends would get the wrong spot).
    var hasExactLocation: Bool = true

    /// Can go in a group pick (and the widget/iMessage): everything except
    /// your own places that have no address.
    var isShareable: Bool { !isCustom || hasExactLocation }

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
        address = place.address ?? ""
        savedAt = .now
    }

    /// Rebuilds a Place, measuring distance from the current search center.
    func asPlace(from center: CLLocationCoordinate2D) -> Place {
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let there = CLLocation(latitude: latitude, longitude: longitude)
        return Place(id: placeID, name: name, category: category,
                     latitude: latitude, longitude: longitude,
                     distanceMeters: here.distance(from: there),
                     phoneNumber: phoneNumber, websiteURL: websiteURL,
                     address: address.isEmpty ? nil : address)
    }

    /// A restaurant you add yourself. Its ID starts with "custom|" so it can
    /// never collide with an Apple Maps place.
    init(customName name: String, category: String, list: SavedList,
         latitude: Double, longitude: Double, address: String, hasExactLocation: Bool) {
        listRaw = list.rawValue
        placeID = "custom|" + UUID().uuidString
        self.name = name
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.hasExactLocation = hasExactLocation
        isCustom = true
        savedAt = .now
    }
}

/// An area you added on the Lists tab ("Nashville, TN", "Chevy Chase"), so you
/// can filter your lists there and add places before you've saved any.
@Model
final class SavedArea {
    var name: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var addedAt: Date = Date()

    init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        addedAt = .now
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Saved places count as "in" an area within the same distance as a metro.
    func contains(_ item: SavedPlace) -> Bool {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: item.latitude, longitude: item.longitude)) <= Metro.radiusMeters
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

/// A place you got directions to. A while later ForkRoad asks "How was it?"
/// and uses the answer to keep your lists accurate.
@Model
final class Visit {
    var visitID: String = UUID().uuidString
    var placeID: String = ""
    var name: String = ""
    var category: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var phoneNumber: String?
    var websiteURL: URL?
    var address: String?
    var startedAt: Date = Date()
    /// Set once the user answers (or dismisses) "How was it?".
    var answeredAt: Date?
    /// "loved", "fine", "never", or "skipped".
    var answer: String = ""

    init(place: Place) {
        visitID = UUID().uuidString
        placeID = place.id
        name = place.name
        category = place.category
        latitude = place.latitude
        longitude = place.longitude
        phoneNumber = place.phoneNumber
        websiteURL = place.websiteURL
        address = place.address
        startedAt = .now
    }

    var place: Place {
        Place(id: placeID, name: name, category: category, latitude: latitude, longitude: longitude,
              distanceMeters: 0, phoneNumber: phoneNumber, websiteURL: websiteURL, address: address)
    }
}
