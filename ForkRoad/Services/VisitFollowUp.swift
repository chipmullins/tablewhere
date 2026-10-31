import Foundation
import SwiftData
import UserNotifications
import PickerCore

/// "How was it?" — after you get directions somewhere, ForkRoad asks how it went
/// (in the app, and with a quiet notification) and files the answer for you.
@MainActor
enum VisitFollowUp {
    static let categoryID = "VISIT_FOLLOW_UP"
    static let lovedAction = "VISIT_LOVED"
    static let fineAction = "VISIT_FINE"
    static let neverAction = "VISIT_NEVER"

    enum Answer: String {
        case loved, fine, never, skipped
    }

    /// Settings toggle (on by default).
    static var remindersOn: Bool {
        get { UserDefaults.standard.object(forKey: "visitReminders") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "visitReminders") }
    }

    /// The notification actions. Call once at launch.
    static func registerCategory() {
        let loved = UNNotificationAction(identifier: lovedAction, title: "❤️ Loved it")
        let fine = UNNotificationAction(identifier: fineAction, title: "👍 It was fine")
        let never = UNNotificationAction(identifier: neverAction, title: "👎 Never again", options: [.destructive])
        let category = UNNotificationCategory(identifier: categoryID, actions: [loved, fine, never],
                                              intentIdentifiers: [], options: [])
        // One call sets every category, so the leave-by reminder's goes here too.
        UNUserNotificationCenter.current().setNotificationCategories([category, LeaveBy.category])
    }

    // MARK: Recording

    /// Call when someone heads to a place (directions). Ignores repeats within 3 hours.
    static func record(_ place: Place, in context: ModelContext) {
        let id = place.id
        let since = Date().addingTimeInterval(-3 * 3600)
        let recent = FetchDescriptor<Visit>(predicate: #Predicate { $0.placeID == id && $0.startedAt > since })
        if ((try? context.fetchCount(recent)) ?? 0) > 0 { return }

        let visit = Visit(place: place)
        context.insert(visit)
        if remindersOn { Task { await scheduleReminder(for: visit) } }
    }

    /// A quiet notification ~2.5 hours later, or 11 AM the next day if that's late at night.
    private static func scheduleReminder(for visit: Visit) async {
        let center = UNUserNotificationCenter.current()
        // Provisional: delivered quietly to Notification Center without a permission prompt.
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .provisional])
        }

        var fireDate = visit.startedAt.addingTimeInterval(2.5 * 3600)
        let hour = Calendar.current.component(.hour, from: fireDate)
        if hour >= 22 || hour < 9 {
            let morning = Calendar.current.startOfDay(for: fireDate.addingTimeInterval(hour >= 22 ? 86_400 : 0))
            fireDate = morning.addingTimeInterval(11 * 3600)
        }

        let content = UNMutableNotificationContent()
        content.title = "How was \(visit.name)?"
        content.body = "Press and hold to rate it. Your lists update automatically."
        content.categoryIdentifier = categoryID
        content.userInfo = ["visitID": visit.visitID]
        content.sound = .default

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(identifier: visit.visitID, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        try? await center.add(request)
    }

    // MARK: Answering

    /// The visit to ask about now, if any: unanswered, 90 minutes to 3 days old.
    static func pending(in context: ModelContext) -> Visit? {
        let newest = Date().addingTimeInterval(-90 * 60)
        let oldest = Date().addingTimeInterval(-3 * 86_400)
        var descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate { $0.answeredAt == nil && $0.startedAt < newest && $0.startedAt > oldest },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func visit(withID id: String, in context: ModelContext) -> Visit? {
        var descriptor = FetchDescriptor<Visit>(predicate: #Predicate { $0.visitID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Files the answer: Loved → Favorites, Never again → Blacklist.
    static func answer(_ visit: Visit, _ answer: Answer, in context: ModelContext) {
        let actions = ListActions(context: context)
        let place = visit.place
        switch answer {
        case .loved:
            if actions.list(for: place) != .favorites { actions.toggle(place, in: .favorites) }
        case .never:
            actions.block(place)
        case .fine, .skipped:
            break
        }
        visit.answer = answer.rawValue
        visit.answeredAt = .now
        try? context.save()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [visit.visitID])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [visit.visitID])
    }
}
