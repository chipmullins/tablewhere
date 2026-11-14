import Foundation
import CoreLocation
import MapKit
import UserNotifications
import PickerCore

/// "Leave by 6:38 PM · 17 min drive": once a group has a place and a meeting
/// time, each phone works out its own drive time with Apple Maps (traffic
/// included) and reminds you when it's time to go.
///
/// Everything happens on the phone: your location never leaves it, and the
/// reminder is a local notification, so it works without server pushes.
/// Shared by the app and the iMessage app; the app adds its own pieces in
/// ForkRoad/Services/LeaveBy+App.swift.
@MainActor
enum LeaveBy {
    /// Extra minutes to park and walk in.
    static let buffer: TimeInterval = 5 * 60

    static let categoryID = "LEAVE_BY"
    static let directionsAction = "LEAVE_BY_DIRECTIONS"
    /// "I'm on my way" (1.1): opens the app and shares your arrival time.
    /// Opens it (foreground) because live arrival updates can only start there.
    static let onMyWayAction = "LEAVE_BY_ON_MY_WAY"

    /// Notification buttons. Registered with VisitFollowUp's category at launch.
    static var category: UNNotificationCategory {
        let onMyWay = UNNotificationAction(identifier: onMyWayAction, title: "I’m on my way", options: [.foreground])
        let go = UNNotificationAction(identifier: directionsAction, title: "Directions", options: [.foreground])
        return UNNotificationCategory(identifier: categoryID, actions: [onMyWay, go], intentIdentifiers: [], options: [])
    }

    /// The "Remind me when it's time to leave" switch (on by default).
    static var remindersOn: Bool {
        get { SharedDefaults.store.object(forKey: "leaveByReminders") as? Bool ?? true }
        set { SharedDefaults.store.set(newValue, forKey: "leaveByReminders") }
    }

    /// Where a drive time is measured from.
    struct Origin {
        let coordinate: CLLocationCoordinate2D
        /// True for a GPS fix; false for a search area or city.
        let isGPS: Bool
        /// "your search area" / "Lexington, KY", shown when not GPS.
        let label: String
    }

    struct Plan: Equatable {
        /// When to leave (already includes the parking buffer).
        let leaveAt: Date
        let meetTime: Date
        /// Drive time, in seconds.
        let travel: TimeInterval
        /// False when we measured from your search area (no GPS fix).
        let fromCurrentLocation: Bool

        var driveMinutes: Int { max(1, Int((travel / 60).rounded())) }
        // Compared as seconds, not with Date's operators: comparing Dates
        // through Comparable crashed on device (null witness, iOS 17 target).
        var isTimeToGo: Bool { leaveAt.timeIntervalSinceNow <= 0 }

        /// Minutes you'd be late leaving right now (0 if you'd make it).
        var minutesLateIfLeavingNow: Int {
            max(0, Int((Date.now.addingTimeInterval(travel).timeIntervalSince(meetTime) / 60).rounded(.up)))
        }
    }

    /// Works out when to leave. Nil if Apple Maps can't find a driving route.
    static func plan(to destination: CLLocationCoordinate2D, meetTime: Date,
                     from origin: CLLocationCoordinate2D, isGPS: Bool) async -> Plan? {
        // First guess, then again for the real departure time so traffic matches.
        let firstGuess = notBeforeNow(meetTime.addingTimeInterval(-30 * 60))
        guard let first = await driveTime(from: origin, to: destination, departing: firstGuess) else { return nil }
        let departure = notBeforeNow(meetTime.addingTimeInterval(-first - buffer))
        let travel = await driveTime(from: origin, to: destination, departing: departure) ?? first
        let leaveAt = meetTime.addingTimeInterval(-travel - buffer)
        // Round down to the minute ("6:38", not "6:38:41").
        let clean = Date(timeIntervalSinceReferenceDate: (leaveAt.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        return Plan(leaveAt: clean, meetTime: meetTime, travel: travel, fromCurrentLocation: isGPS)
    }

    /// The date, or now if it's already passed (without Date's comparison operators).
    private static func notBeforeNow(_ date: Date) -> Date {
        date.timeIntervalSinceNow > 0 ? date : Date()
    }

    private static func driveTime(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                                  departing: Date) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        request.departureDate = departing
        return try? await MKDirections(request: request).calculateETA().expectedTravelTime
    }

    // MARK: Reminders

    private static func requestID(_ sessionID: String) -> String { "leaveby.\(sessionID)" }
    private static func headsUpID(_ sessionID: String) -> String { "headsup.\(sessionID)" }

    /// The heads-up goes out this long before the meet time ("Lock Screen
    /// countdown starts", 1–8 hours). Tapping it opens the plan, which starts
    /// the countdown. Only on phones where the server can't start it
    /// (iOS 17.0–17.1, or no push-to-start token yet).
    static var headsUpBeforeMeet: TimeInterval { LiveActivitySettings.lead }

    /// The leave-by last saved for each plan, so a refresh that changes
    /// nothing doesn't write again.
    private static var savedPlans: [String: TimeInterval] = [:]

    /// Schedules (or replaces) the "Time to head out" reminder for a group.
    /// `mayAsk`: whether this may show the notification permission prompt.
    /// Only the leave-by card asks (where it's clear why); the background
    /// refresh when the app opens never does.
    /// `title`: the group's name, for the Live Activity (nil shows "Group plan").
    static func schedule(_ plan: Plan, sessionID: String, winner: GroupOption, title: String? = nil,
                         mayAsk: Bool = true) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID(sessionID), headsUpID(sessionID)])
        // Before the reminder checks: the Live Activity also covers "Time to go"
        // after leave-by passes, and checks the reminder switch itself.
        activityUpdate?(plan, sessionID, winner, title)
        // So a countdown the server starts shows your leave-by time.
        if savedPlans[sessionID] != plan.leaveAt.timeIntervalSinceReferenceDate,
           (try? await GroupService.shared.saveLeavePlan(sessionID: sessionID, leaveAt: plan.leaveAt,
                                                         travelMinutes: plan.driveMinutes,
                                                         meetTime: plan.meetTime)) != nil {
            // Only once it's saved, so a failed write is tried again next refresh.
            savedPlans[sessionID] = plan.leaveAt.timeIntervalSinceReferenceDate
        }
        guard remindersOn, plan.leaveAt.timeIntervalSinceNow > 60 else { return }

        // "Provisional" (quiet) permission from "How was it?" would deliver
        // this silently, so ask for the real thing then too.
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined || settings.authorizationStatus == .provisional {
            if mayAsk { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
            else if settings.authorizationStatus == .notDetermined { return }
        }

        let content = UNMutableNotificationContent()
        content.title = "Time to head to \(winner.name)"
        content.body = "Leave now to make \(plan.meetTime.formatted(date: .omitted, time: .shortened)). "
            + "About \(plan.driveMinutes) min drive."
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["sessionId": sessionID, "name": winner.name,
                            "lat": winner.latitude, "lon": winner.longitude,
                            "meet": plan.meetTime.timeIntervalSince1970]

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.leaveAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: requestID(sessionID), content: content, trigger: trigger))

        // The heads-up, at the chosen lead time. Skipped when the server
        // starts the countdown itself, when it's already that close, or when
        // leave-by comes first or right after (that reminder covers it).
        guard !LiveActivitySettings.serverStartsIt else { return }
        let headsUpAt = plan.meetTime.addingTimeInterval(-headsUpBeforeMeet)
        guard headsUpAt.timeIntervalSinceNow > 60,
              plan.leaveAt.timeIntervalSince(headsUpAt) > 15 * 60 else { return }
        let time = plan.meetTime.formatted(date: .omitted, time: .shortened)
        let heads = UNMutableNotificationContent()
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        heads.title = name.isEmpty ? "\(winner.name) at \(time)" : "\(name): \(winner.name) at \(time)"
        heads.body = "Leave by \(plan.leaveAt.formatted(date: .omitted, time: .shortened)) (about \(plan.driveMinutes) min). "
            + "Tap for your Lock Screen countdown."
        heads.sound = .default
        heads.userInfo = ["sessionId": sessionID]
        let headsParts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: headsUpAt)
        try? await center.add(UNNotificationRequest(
            identifier: headsUpID(sessionID), content: heads,
            trigger: UNCalendarNotificationTrigger(dateMatching: headsParts, repeats: false)))
    }

    static func cancel(sessionID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestID(sessionID), headsUpID(sessionID)])
        activityEnd?(sessionID)
        // No plan anymore (or a changed one): stop "On my way" and forget it.
        OnMyWay.reset(sessionID: sessionID)
    }

    // MARK: Live Activity

    /// Shows or updates the plan's Live Activity (Lock Screen and Dynamic Island).
    /// Set by the app at launch (`LiveActivities.install()`, in
    /// ForkRoad/Services/LiveActivities.swift). Stays nil in the iMessage
    /// extension, which can't start Live Activities, so there it does nothing.
    static var activityUpdate: (@MainActor (_ plan: Plan, _ sessionID: String,
                                            _ winner: GroupOption, _ title: String?) -> Void)?

    /// Ends the plan's Live Activity. Nil (no-op) outside the app, like `activityUpdate`.
    static var activityEnd: (@MainActor (_ sessionID: String) -> Void)?
}
