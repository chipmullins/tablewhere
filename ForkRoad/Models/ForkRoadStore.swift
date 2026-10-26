import Foundation
import SwiftData

/// The app's SwiftData container.
///
/// `cloudKitDatabase: .automatic` syncs through the iCloud container in the
/// app's entitlements when it's available, and quietly stays on-device when it
/// isn't (no iCloud account, or the Developer Program isn't active yet).
///
/// CloudKit rule to remember: once synced, models can only change additively —
/// add new properties with defaults, never rename or delete.
enum ForkRoadStore {
    static let schema = Schema([
        SavedPlace.self,
        BlockedPlace.self,
        BlockedCategory.self,
        SpinRecord.self,
        Trip.self,
        TripPlace.self,
        Visit.self
    ])

    static let container: ModelContainer = {
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // Fall back to on-device storage rather than failing to launch.
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Couldn’t create the data store: \(error)")
            }
        }
    }()
}
