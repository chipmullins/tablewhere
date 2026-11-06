import Foundation

/// IDs and hosts shared by the app and the iMessage extension.
enum AppConfig {
    /// App Group that lets the app and the iMessage extension share small bits of data.
    static let appGroup = "group.com.chipmullins.forkroad"

    /// Where the web vote page is hosted. After creating your Firebase project,
    /// change this to "<your-project-id>.web.app" (see README → Firebase setup).
    static let webHost = "forkroad-app.web.app"
}

/// UserDefaults shared between the app and the extension.
enum SharedDefaults {
    static let store = UserDefaults(suiteName: AppConfig.appGroup) ?? .standard
}

/// The name friends see in group votes.
enum Identity {
    private static let key = "displayName"

    static var displayName: String? {
        get {
            let name = SharedDefaults.store.string(forKey: key)?.trimmingCharacters(in: .whitespaces)
            return (name?.isEmpty ?? true) ? nil : name
        }
        set { SharedDefaults.store.set(newValue, forKey: key) }
    }
}

/// App-wide preferences that both the app and the extension respect.
enum Preferences {
    static let noFastFoodKey = "excludeFastFood"

    static var excludeFastFood: Bool {
        get { SharedDefaults.store.object(forKey: noFastFoodKey) as? Bool ?? true }
        set { SharedDefaults.store.set(newValue, forKey: noFastFoodKey) }
    }

    static let noCoffeeSweetsKey = "excludeCoffeeAndSweets"

    /// "No coffee & sweets": on until you turn it off.
    static var excludeCoffeeAndSweets: Bool {
        get { SharedDefaults.store.object(forKey: noCoffeeSweetsKey) as? Bool ?? true }
        set { SharedDefaults.store.set(newValue, forKey: noCoffeeSweetsKey) }
    }
}
