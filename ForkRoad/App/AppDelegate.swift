import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

/// Handles notifications: "How was it?" actions and group pick pushes.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in VisitFollowUp.registerCategory() }

        if FirebaseSetup.configureIfPossible() {
            Messaging.messaging().delegate = self
            // Only re-register if the user already allowed notifications; the
            // permission prompt itself happens when they start or join a group.
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                guard settings.authorizationStatus == .authorized else { return }
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebaseSetup.isConfigured else { return }
        Messaging.messaging().apnsToken = deviceToken
    }

    // MARK: MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            PushTokens.current = fcmToken
            await GroupService.shared.updatePushToken(fcmToken)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show banners even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo

        if let visitID = info["visitID"] as? String {
            await MainActor.run {
                let context = ForkRoadStore.container.mainContext
                guard let visit = VisitFollowUp.visit(withID: visitID, in: context) else { return }
                switch response.actionIdentifier {
                case VisitFollowUp.lovedAction: VisitFollowUp.answer(visit, .loved, in: context)
                case VisitFollowUp.fineAction: VisitFollowUp.answer(visit, .fine, in: context)
                case VisitFollowUp.neverAction: VisitFollowUp.answer(visit, .never, in: context)
                default: break  // Tapped the banner: the app shows the "How was it?" sheet.
                }
            }
            return
        }

        if response.actionIdentifier == LeaveBy.directionsAction {
            await MainActor.run { LeaveBy.openDirections(from: info) }
            return
        }

        if let sessionID = info["sessionId"] as? String {
            await MainActor.run { DeepLink.post("group:\(sessionID)") }
        }
    }
}

/// The FCM token for this device, shared with the iMessage extension.
enum PushTokens {
    static var current: String? {
        get { SharedDefaults.store.string(forKey: "fcmToken") }
        set { SharedDefaults.store.set(newValue, forKey: "fcmToken") }
    }

    /// Asks for notification permission (for group picks) and registers for pushes.
    @MainActor
    static func requestGroupAlerts() async {
        // Asked even without group pushes: leave-by reminders are local.
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted && FirebaseSetup.isConfigured { UIApplication.shared.registerForRemoteNotifications() }
    }
}

/// Deep links from notifications, Siri, widgets, and forkroad:// URLs:
/// "spin", "discover", "lists", "group:<sessionID>".
enum DeepLink {
    static let key = "pendingDeepLink"
    static let notification = Notification.Name("ForkRoadDeepLink")

    @MainActor
    static func post(_ link: String) {
        SharedDefaults.store.set(link, forKey: key)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// Returns and clears the pending link.
    static func take() -> String? {
        guard let link = SharedDefaults.store.string(forKey: key) else { return nil }
        SharedDefaults.store.removeObject(forKey: key)
        return link
    }
}
