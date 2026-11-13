import Foundation

/// "Remove from Lock Screen" (Settings → Group plans).
enum LockScreenRemoval: String, CaseIterable, Identifiable {
    /// When "On my way" sees you arrive. Without it, 30 min after the meet time.
    case arrive
    case meet
    case after30
    case after60

    var id: Self { self }

    var title: String {
        switch self {
        case .arrive: return "When I arrive"
        case .meet: return "At the meet time"
        case .after30: return "30 min after"
        case .after60: return "1 hour after"
        }
    }

    /// How long it stays after the meet time when nothing else takes it down
    /// ("When I arrive" falls back to 30 minutes).
    var linger: TimeInterval {
        switch self {
        case .meet: return 0
        case .arrive, .after30: return 30 * 60
        case .after60: return 60 * 60
        }
    }
}

/// When the group plan Live Activity starts and goes away, and the
/// ActivityKit push tokens the server needs to start, update, and end it
/// (1.1). Saved in the app group, so the app, the iMessage extension, and
/// the widget read the same values; copied to `sessions/{id}/devices/{uid}`
/// in each plan you join (GroupService.saveDevice), which only you and the
/// server can read.
enum LiveActivitySettings {
    private static var store: UserDefaults { SharedDefaults.store }

    /// "Lock Screen countdown starts" this many hours before the meet time
    /// (iOS keeps an activity up for about 8 hours). Default 2.
    static let leadRange = 1...8
    static var leadHours: Int {
        get {
            let value = store.object(forKey: "la.leadHours") as? Int ?? 2
            return min(max(value, leadRange.lowerBound), leadRange.upperBound)
        }
        set { store.set(min(max(newValue, leadRange.lowerBound), leadRange.upperBound), forKey: "la.leadHours") }
    }
    static var lead: TimeInterval { TimeInterval(leadHours) * 3600 }

    static var removal: LockScreenRemoval {
        get { (store.string(forKey: "la.removal")).flatMap(LockScreenRemoval.init(rawValue:)) ?? .arrive }
        set { store.set(newValue.rawValue, forKey: "la.removal") }
    }

    /// The ActivityKit push-to-start token (iOS 17.2+), hex. Nil before
    /// iOS hands one over, on iOS 17.0–17.1, or with Live Activities off.
    static var startToken: String? {
        get { store.string(forKey: "la.startToken") }
        set { store.set(newValue, forKey: "la.startToken") }
    }

    /// Live Activities are allowed for Tablewhere (Settings → Tablewhere).
    static var activitiesEnabled: Bool {
        get { store.object(forKey: "la.enabled") as? Bool ?? true }
        set { store.set(newValue, forKey: "la.enabled") }
    }

    /// The leave-by reminder switch (LeaveBy.remindersOn): off means no
    /// countdown from the server either.
    static var countdownOn: Bool { store.object(forKey: "leaveByReminders") as? Bool ?? true }

    /// The server starts the countdown on this phone (push-to-start), so
    /// the old heads-up notification isn't needed.
    static var serverStartsIt: Bool { startToken != nil && activitiesEnabled }

    /// Which APNs servers this build's tokens belong to. TestFlight and App
    /// Store builds are Release, which use production.
    static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}
