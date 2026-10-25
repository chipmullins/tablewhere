import Foundation
import FirebaseCore
import FirebaseAuth

/// Starts Firebase if GoogleService-Info.plist is in the bundle.
///
/// The plist isn't committed to Git (see README → Firebase setup). Without it,
/// everything except group voting still works.
enum FirebaseSetup {
    private(set) static var isConfigured = false

    /// Keychain group shared by the app and the iMessage extension, so both use
    /// the same anonymous sign-in. That way a vote started in Messages can be
    /// locked in from the app, and vice versa.
    static let sharedKeychainSuffix = "com.chipmullins.forkroad.shared"

    @discardableResult
    static func configureIfPossible() -> Bool {
        if isConfigured { return true }
        if FirebaseApp.app() == nil {
            guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
                return false
            }
            FirebaseApp.configure()
        }
        shareSignInWithExtension()
        isConfigured = true
        return true
    }

    private static func shareSignInWithExtension() {
        // "ABCDE12345." — filled in at build time from the signing team.
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !prefix.isEmpty, !prefix.hasPrefix("$") else { return }
        try? Auth.auth().useUserAccessGroup(prefix + sharedKeychainSuffix)
    }
}
