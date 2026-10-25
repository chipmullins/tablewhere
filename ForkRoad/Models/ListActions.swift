import Foundation
import SwiftData
import PickerCore

/// Save, block, and spin-history actions, in one place so every screen
/// behaves the same way and duplicates never get stored.
@MainActor
struct ListActions {
    let context: ModelContext

    // MARK: Interested list

    func isSaved(_ place: Place) -> Bool {
        savedRecord(for: place.id) != nil
    }

    func toggleSaved(_ place: Place) {
        if let existing = savedRecord(for: place.id) {
            context.delete(existing)
        } else {
            context.insert(SavedPlace(place: place))
        }
    }

    // MARK: Blocking

    func isBlocked(_ place: Place) -> Bool {
        let id = place.id
        let descriptor = FetchDescriptor<BlockedPlace>(predicate: #Predicate { $0.placeID == id })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func block(_ place: Place) {
        guard !isBlocked(place) else { return }
        context.insert(BlockedPlace(place: place))
        // A blocked place shouldn't stay on the Interested list.
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
