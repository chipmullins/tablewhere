import Foundation
import CoreLocation

/// A place the user searches around instead of their GPS location.
struct ChosenLocation: Codable, Hashable, Identifiable {
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double

    var id: String { "\(name)|\(latitude)|\(longitude)" }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // MARK: Saved between launches (on this device)

    private static let savedKey = "location.chosen"
    private static let recentKey = "location.recent"

    static var saved: ChosenLocation? {
        get { load(savedKey) }
        set { store(newValue, savedKey) }
    }

    /// Up to 5 recent picks, newest first.
    static var recent: [ChosenLocation] {
        let list: [ChosenLocation]? = load(recentKey)
        return list ?? []
    }

    static func remember(_ place: ChosenLocation) {
        var list = recent.filter { $0.id != place.id }
        list.insert(place, at: 0)
        store(Array(list.prefix(5)), recentKey)
    }

    static func forget(_ place: ChosenLocation) {
        store(recent.filter { $0.id != place.id }, recentKey)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func store<T: Encodable>(_ value: T?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}
