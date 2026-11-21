import Foundation
import PickerCore

/// Remembers the most specific label each place has been given.
///
/// MapKit has no cuisine data: a place is "Mexican" when a Mexican search
/// finds it and just "Restaurant" in an "All" search. Without this, the same
/// taqueria changes label (and icon) from one search to the next. Once a
/// place has earned a real label, it keeps it. Kept on the device, capped,
/// oldest dropped first.
final class LabelMemory: @unchecked Sendable {
    static let shared = LabelMemory()

    private static let key = "search.labels"
    private static let cap = 3_000
    /// Labels that say nothing about the food, so they never replace a real one.
    private static let generic: Set<String> = ["Restaurant"]
    /// Diet searches label by diet; a diet isn't a cuisine, so it isn't kept.
    private static let notCuisines: Set<String> = Set(DietFilter.allCases.map(\.label))

    private let lock = NSLock()
    private var labels: [String: String]
    private var order: [String]
    private var dirty = false

    private init() {
        let saved = SharedDefaults.store.dictionary(forKey: Self.key) as? [String: [String]] ?? [:]
        let ids = saved["ids"] ?? [], values = saved["labels"] ?? []
        var labels: [String: String] = [:]
        for (id, label) in zip(ids, values) { labels[id] = label }
        self.labels = labels
        self.order = ids.filter { labels[$0] != nil }
    }

    /// Learns from these results and fills in a remembered label wherever a
    /// result only says "Restaurant".
    func apply(_ places: [Place]) -> [Place] {
        lock.lock(); defer { lock.unlock() }
        let result = places.map { place -> Place in
            if Self.generic.contains(place.category) {
                guard let remembered = labels[place.id] else { return place }
                return place.relabeled(remembered)
            }
            if !Self.notCuisines.contains(place.category), labels[place.id] != place.category {
                if labels[place.id] == nil { order.append(place.id) }
                labels[place.id] = place.category
                dirty = true
            }
            return place
        }
        if order.count > Self.cap {
            for id in order.prefix(order.count - Self.cap) { labels[id] = nil }
            order.removeFirst(order.count - Self.cap)
        }
        if dirty { save() }
        return result
    }

    private func save() {
        dirty = false
        SharedDefaults.store.set(["ids": order, "labels": order.map { labels[$0] ?? "" }], forKey: Self.key)
    }
}

private extension Place {
    func relabeled(_ category: String) -> Place {
        Place(id: id, name: name, category: category, latitude: latitude, longitude: longitude,
              distanceMeters: distanceMeters, phoneNumber: phoneNumber, websiteURL: websiteURL,
              address: address)
    }
}
