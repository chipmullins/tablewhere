import Foundation

/// Meeting-time choices for a decided group pick.
///
/// Times snap to quarter hours (:00, :15, :30, :45) so the buttons read
/// "6:45 PM", never "6:31 PM".
public enum MeetTimes {
    /// Minutes between suggested slots.
    public static let step = 15

    /// Quick-pick slots: the first quarter hour at least `lead` minutes out,
    /// then every 15 minutes after it.
    public static func slots(from now: Date = Date(), lead: Int = 15, count: Int = 5,
                             calendar: Calendar = .current) -> [Date] {
        let earliest = now.addingTimeInterval(TimeInterval(lead * 60))
        let first = nextQuarterHour(onOrAfter: earliest, calendar: calendar)
        return (0..<count).compactMap { calendar.date(byAdding: .minute, value: $0 * step, to: first) }
    }

    /// Rounds up to the next :00/:15/:30/:45 with zero seconds.
    /// A time already on a quarter hour (with zero seconds) stays put.
    public static func nextQuarterHour(onOrAfter date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        let minute = parts.minute ?? 0
        let hasSeconds = (parts.second ?? 0) > 0 || (parts.nanosecond ?? 0) > 0
        var add = (step - minute % step) % step
        if add == 0 && hasSeconds { add = step }
        var floor = parts
        floor.second = 0
        floor.nanosecond = 0
        let start = calendar.date(from: floor) ?? date
        return calendar.date(byAdding: .minute, value: add, to: start) ?? date
    }

    /// A custom time picked on a clock face (hour and minute only): today if
    /// that's still ahead of `now`, otherwise the same time tomorrow.
    public static func resolve(hour: Int, minute: Int, after now: Date = Date(),
                               calendar: Calendar = .current) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        let today = calendar.date(from: parts) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
