import Foundation
import CoreLocation
import MapKit
import UIKit
import UserNotifications
import FirebaseFirestore
import PickerCore

/// "Leave by 6:38 PM · 17 min drive": once a group has a place and a meeting
/// time, each phone works out its own drive time with Apple Maps (traffic
/// included) and reminds you when it's time to go.
///
/// Everything happens on the phone: your location never leaves it, and the
/// reminder is a local notification, so it works without server pushes.
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
        get { UserDefaults.standard.object(forKey: "leaveByReminders") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "leaveByReminders") }
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
        var isTimeToGo: Bool { leaveAt <= .now }

        /// Minutes you'd be late leaving right now (0 if you'd make it).
        var minutesLateIfLeavingNow: Int {
            max(0, Int((Date.now.addingTimeInterval(travel).timeIntervalSince(meetTime) / 60).rounded(.up)))
        }
    }

    /// Where to measure from: your GPS location if we have it, else the area you're searching.
    static func origin(_ model: AppModel) -> (coordinate: CLLocationCoordinate2D, isGPS: Bool) {
        if let gps = model.location.coordinate { return (gps, true) }
        return (model.center, false)
    }

    /// Works out when to leave. Nil if Apple Maps can't find a driving route.
    static func plan(to destination: CLLocationCoordinate2D, meetTime: Date,
                     from origin: CLLocationCoordinate2D, isGPS: Bool) async -> Plan? {
        // First guess, then again for the real departure time so traffic matches.
        let firstGuess = max(Date.now, meetTime.addingTimeInterval(-30 * 60))
        guard let first = await driveTime(from: origin, to: destination, departing: firstGuess) else { return nil }
        let departure = max(Date.now, meetTime.addingTimeInterval(-first - buffer))
        let travel = await driveTime(from: origin, to: destination, departing: departure) ?? first
        let leaveAt = meetTime.addingTimeInterval(-travel - buffer)
        // Round down to the minute ("6:38", not "6:38:41").
        let clean = Date(timeIntervalSinceReferenceDate: (leaveAt.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        return Plan(leaveAt: clean, meetTime: meetTime, travel: travel, fromCurrentLocation: isGPS)
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
        guard remindersOn, plan.leaveAt > Date.now.addingTimeInterval(60) else { return }

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

    /// Sets up reminders for every recent group that's decided with a time
    /// ahead (and clears ones that ended or changed). Run when the app opens,
    /// so you get reminded even if you never opened the group after the time was set.
    static func refreshAll(_ model: AppModel) async {
        guard FirebaseSetup.isConfigured, (try? await GroupService.shared.userID()) != nil else { return }
        for id in SharedCache.recentSessionIDs().prefix(5) {
            guard let session = try? await GroupService.shared.sessionRef(id).getDocument(as: GroupSession.self),
                  session.status == .decided, let winner = session.winner,
                  let meet = session.meetTime, meet > .now else {
                cancel(sessionID: id)
                continue
            }
            let from = origin(model)
            if let plan = await plan(to: CLLocationCoordinate2D(latitude: winner.latitude, longitude: winner.longitude),
                                     meetTime: meet, from: from.coordinate, isGPS: from.isGPS) {
                await schedule(plan, sessionID: id, winner: winner, mayAsk: false)
            }
        }
    }

    /// The notification's Directions button.
    static func openDirections(from info: [AnyHashable: Any]) {
        guard let lat = info["lat"] as? Double, let lon = info["lon"] as? Double else { return }
        let name = (info["name"] as? String)?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://maps.apple.com/?daddr=\(lat),\(lon)&q=\(name)&dirflg=d") {
            UIApplication.shared.open(url)
        }
    }
}
