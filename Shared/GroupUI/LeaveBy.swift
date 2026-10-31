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

    /// Notification buttons. Registered with VisitFollowUp's category at launch.
    static var category: UNNotificationCategory {
        let go = UNNotificationAction(identifier: directionsAction, title: "Directions", options: [.foreground])
        return UNNotificationCategory(identifier: categoryID, actions: [go], intentIdentifiers: [], options: [])
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

    /// Schedules (or replaces) the "Time to head out" reminder for a group.
    /// `mayAsk`: whether this may show the notification permission prompt.
    /// Only the leave-by card asks (where it's clear why); the background
    /// refresh when the app opens never does.
    static func schedule(_ plan: Plan, sessionID: String, winner: GroupOption, mayAsk: Bool = true) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID(sessionID)])
        guard remindersOn, plan.leaveAt.timeIntervalSinceNow > 60 else { return }

        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard mayAsk else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let content = UNMutableNotificationContent()
        content.title = "Time to head to \(winner.name)"
        content.body = "Leave now to make \(plan.meetTime.formatted(date: .omitted, time: .shortened)). "
            + "About \(plan.driveMinutes) min drive."
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["sessionId": sessionID, "name": winner.name,
                            "lat": winner.latitude, "lon": winner.longitude]

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.leaveAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: requestID(sessionID), content: content, trigger: trigger))
    }

    static func cancel(sessionID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestID(sessionID)])
    }
}
