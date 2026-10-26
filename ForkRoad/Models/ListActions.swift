import Foundation
import CoreLocation
import SwiftData
import PickerCore

/// Save, blacklist, and spin-history actions, in one place so every screen
/// behaves the same way and duplicates never get stored.
@MainActor
struct ListActions {
    let context: ModelContext

    // MARK: Favorites & Interested

    /// Which list a place is on, if any. A place is on at most one.
    func list(for place: Place) -> SavedList? {
        savedRecord(for: place.id)?.list
    }

    /// Puts a place on `list`, moves it there from the other list, or removes
    /// it if it's already on `list`.
    func toggle(_ place: Place, in list: SavedList) {
        if let existing = savedRecord(for: place.id) {
            if existing.list == list {
                context.delete(existing)
            } else {
                existing.list = list
                existing.savedAt = .now
            }
        } else {
            let item = SavedPlace(place: place, list: list)
            context.insert(item)
            Task { await Self.fillInCity(item) }
        }
    }

    /// Looks up and stores the city for a saved place, if it doesn't have one.
    static func fillInCity(_ item: SavedPlace) async {
        guard item.city.isEmpty else { return }
        let coordinate = CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
        if let city = await CityResolver.city(for: coordinate) {
            item.city = city
        }
    }

    func move(_ item: SavedPlace, to list: SavedList) {
        item.list = list
        item.savedAt = .now
    }

    // MARK: Blacklist

    func isBlocked(_ place: Place) -> Bool {
        let id = place.id
        let descriptor = FetchDescriptor<BlockedPlace>(predicate: #Predicate { $0.placeID == id })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func block(_ place: Place) {
        guard !isBlocked(place) else { return }
        context.insert(BlockedPlace(place: place))
        // A blacklisted place shouldn't stay on Favorites or Interested.
        if let saved = savedRecord(for: place.id) { context.delete(saved) }
    }

    func blockCategory(_ name: String) {
        let lowered = name.lowercased()
        let all = (try? context.fetch(FetchDescriptor<BlockedCategory>())) ?? []
        guard !all.contains(where: { $0.name.lowercased() == lowered }) else { return }
        context.insert(BlockedCategory(name: name))
    }

    // MARK: Spin history

    func recordSpin(_ place: Place) {
        context.insert(SpinRecord(placeID: place.id))
    }

    /// IDs picked in the last `days` days.
    func recentPlaceIDs(days: Int = 7) -> Set<String> {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let descriptor = FetchDescriptor<SpinRecord>(predicate: #Predicate { $0.spunAt >= cutoff })
        let records = (try? context.fetch(descriptor)) ?? []
        return Set(records.map(\.placeID))
    }

    // MARK: Helpers

    private func savedRecord(for id: String) -> SavedPlace? {
        var descriptor = FetchDescriptor<SavedPlace>(predicate: #Predicate { $0.placeID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
