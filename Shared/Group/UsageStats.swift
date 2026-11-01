import Foundation
import FirebaseFirestore

/// What ForkRoad counts. Matches `statFields()` in web/firestore.rules and
/// the stats page (web/public/stats.js).
enum UsageStat: String {
    case activeDevices, newDevices, spins, groupsVote, groupsSpin, groupsPlan, rsvps, groupPicks, customPlaces
}

/// Anonymous daily usage counts for Chip's stats page: one number per thing
/// per day (stats/{yyyy-mm-dd}), nothing else. No names, places, locations,
/// or IDs are stored, and nothing links a count to a person or device.
/// Days are UTC. Turn off in Settings → Share anonymous usage counts.
@MainActor
enum UsageStats {
    private static let onKey = "stats.on"
    private static let lastActiveKey = "stats.lastActiveDay"
    private static let everActiveKey = "stats.everActive"

    static var isOn: Bool {
        get { SharedDefaults.store.object(forKey: onKey) as? Bool ?? true }
        set { SharedDefaults.store.set(newValue, forKey: onKey) }
    }

    /// Today's document ID, in UTC ("2026-10-31").
    static var today: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }

    /// Adds one to today's count. Fire and forget; failures are ignored.
    static func record(_ stat: UsageStat) {
        guard isOn, FirebaseSetup.configureIfPossible() else { return }
        let day = today
        Task {
            // Writing needs the same anonymous sign-in group picks use.
            guard (try? await GroupService.shared.userID()) != nil else { return }
            try? await Firestore.firestore().collection("stats").document(day)
                .setData([stat.rawValue: FieldValue.increment(Int64(1))], merge: true)
        }
    }

    /// Counts this device once per day (the app and the iMessage app share
    /// the check, so using both still counts once). The first day ever also
    /// counts as a new device.
    static func recordActiveDevice() {
        let day = today
        guard isOn, SharedDefaults.store.string(forKey: lastActiveKey) != day else { return }
        SharedDefaults.store.set(day, forKey: lastActiveKey)
        record(.activeDevices)
        if !SharedDefaults.store.bool(forKey: everActiveKey) {
            SharedDefaults.store.set(true, forKey: everActiveKey)
            record(.newDevices)
        }
    }
}
