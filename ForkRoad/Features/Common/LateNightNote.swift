import SwiftUI

/// From 10 PM to 5 AM (your local time): a quiet reminder that some places
/// will be closed. Apple Maps doesn't give ForkRoad opening hours, so the
/// app can't tell which.
struct LateNightNote: View {
    var body: some View {
        // Re-checked each minute, so it appears (and goes) on its own.
        TimelineView(.everyMinute) { context in
            if Self.isLate(context.date) {
                Label("It’s late, so some places may be closed. Call or check hours before you go.",
                      systemImage: "moon.stars")
                    .font(Theme.body(13, .medium))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    static func isLate(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 22 || hour < 5
    }
}
