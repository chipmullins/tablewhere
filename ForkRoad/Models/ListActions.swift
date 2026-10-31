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
                // Your own places are only removed on purpose (Delete), never by
                // tapping the heart/bookmark off; they'd be gone for good.
                guard !existing.isCustom else { return }
                remove(existing)
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

    /// Whether a saved place is left out of spins (false if it isn't saved).
    func isSkippedInSpins(_ place: Place) -> Bool {
        savedRecord(for: place.id)?.skipInSpins ?? false
    }

    func setSkippedInSpins(_ place: Place, _ skipped: Bool) {
        savedRecord(for: place.id)?.skipInSpins = skipped
    }

    /// Takes a place off its list (or deletes your own place), with Undo.
    func remove(_ item: SavedPlace) {
        let snapshot = SavedSnapshot(item)
        let message = item.isCustom ? "Deleted \(item.name)" : "Removed \(item.name) from \(item.list.title)"
        context.delete(item)
        try? context.save()
        UndoCenter.shared.show(message) {
            snapshot.restore(in: context)
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

    /// Blacklists a place, with Undo. `extraUndo` also runs on Undo (e.g. put
    /// it back on your wheel).
    func block(_ place: Place, extraUndo: (@MainActor () -> Void)? = nil) {
        guard !isBlocked(place) else { return }
        let blocked = BlockedPlace(place: place)
        context.insert(blocked)
        // A blacklisted place shouldn't stay on Favorites or Want to try.
        var snapshot: SavedSnapshot?
        if let saved = savedRecord(for: place.id) {
            snapshot = SavedSnapshot(saved)
            context.delete(saved)
        }
        try? context.save()
        UndoCenter.shared.show("Blacklisted \(place.name)") {
            context.delete(blocked)
            snapshot?.restore(in: context)
            try? context.save()
            extraUndo?()
        }
    }

    func blockCategory(_ name: String) {
        let lowered = name.lowercased()
        let all = (try? context.fetch(FetchDescriptor<BlockedCategory>())) ?? []
        guard !all.contains(where: { $0.name.lowercased() == lowered }) else { return }
        let blocked = BlockedCategory(name: name)
        context.insert(blocked)
        try? context.save()
        UndoCenter.shared.show("Blacklisted all \(name)") {
            context.delete(blocked)
            try? context.save()
        }
    }

    /// Takes a place or type off the blacklist, with Undo.
    func unblock(_ item: BlockedPlace) {
        let id = item.placeID, name = item.name, at = item.blockedAt
        context.delete(item)
        try? context.save()
        UndoCenter.shared.show("\(name) is back") {
            let restored = BlockedPlace(place: Place(id: id, name: name, category: "",
                                                     latitude: 0, longitude: 0, distanceMeters: 0))
            restored.blockedAt = at
            context.insert(restored)
            try? context.save()
        }
    }

    func unblock(_ item: BlockedCategory) {
        let name = item.name, at = item.blockedAt
        context.delete(item)
        try? context.save()
        UndoCenter.shared.show("\(name) is back") {
            let restored = BlockedCategory(name: name)
            restored.blockedAt = at
            context.insert(restored)
            try? context.save()
        }
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

    /// The saved record for a place, if it's on a list.
    func saved(_ place: Place) -> SavedPlace? { savedRecord(for: place.id) }

    private func savedRecord(for id: String) -> SavedPlace? {
        var descriptor = FetchDescriptor<SavedPlace>(predicate: #Predicate { $0.placeID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

/// Everything about a saved place, so Undo can put it back exactly.
@MainActor
struct SavedSnapshot {
    let listRaw, city, note, placeID, name, category, address: String
    let skipInSpins, isCustom, hasExactLocation: Bool
    let latitude, longitude: Double
    let phoneNumber: String?
    let websiteURL: URL?
    let savedAt: Date

    init(_ item: SavedPlace) {
        listRaw = item.listRaw; city = item.city; note = item.note; placeID = item.placeID
        name = item.name; category = item.category; address = item.address
        skipInSpins = item.skipInSpins; isCustom = item.isCustom; hasExactLocation = item.hasExactLocation
        latitude = item.latitude; longitude = item.longitude
        phoneNumber = item.phoneNumber; websiteURL = item.websiteURL; savedAt = item.savedAt
    }

    func restore(in context: ModelContext) {
        // Already back (e.g. saved again before Undo): leave it.
        let id = placeID
        var descriptor = FetchDescriptor<SavedPlace>(predicate: #Predicate { $0.placeID == id })
        descriptor.fetchLimit = 1
        guard ((try? context.fetchCount(descriptor)) ?? 0) == 0 else { return }
        let item = SavedPlace(place: Place(id: placeID, name: name, category: category,
                                           latitude: latitude, longitude: longitude, distanceMeters: 0,
                                           phoneNumber: phoneNumber, websiteURL: websiteURL,
                                           address: address.isEmpty ? nil : address),
                              list: SavedList(rawValue: listRaw) ?? .interested)
        item.listRaw = listRaw
        item.city = city
        item.note = note
        item.skipInSpins = skipInSpins
        item.isCustom = isCustom
        item.hasExactLocation = hasExactLocation
        item.savedAt = savedAt
        context.insert(item)
        try? context.save()
    }
}
