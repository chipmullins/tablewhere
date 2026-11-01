import SwiftUI
import CoreLocation
import PickerCore

/// "Leave by 6:38 PM · 17 min drive", worked out on this phone from your
/// location, plus the "remind me" switch.
struct LeaveByCard: View {
    let sessionID: String
    let winner: GroupOption
    let meetTime: Date
    /// The group's name, for the Live Activity (nil shows "Group plan").
    var title: String? = nil
    /// Where to measure from (the app: GPS or search area; iMessage: its
    /// own location or the app's last search area). Nil if there's nowhere.
    let origin: @MainActor () async -> LeaveBy.Origin?
    /// Shown as "Use my location" when we're measuring from an area instead
    /// of GPS. Returns true once location is allowed.
    var askForLocation: (@MainActor () async -> Bool)? = nil
    @State private var plan: LeaveBy.Plan?
    @State private var failed = false
    @State private var remind = LeaveBy.remindersOn
    @State private var originLabel = "where you are"
    @State private var usingGPS = true
    @State private var refreshCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: plan?.isTimeToGo == true ? "car.fill" : "clock.badge")
                    .font(Theme.body(20, .semibold))
                    .foregroundStyle(Theme.onSaffron)
                    .frame(width: 44, height: 44)
                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(Theme.display(20))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    Text(detail)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if plan == nil && !failed { ProgressView().tint(Theme.muted) }
            }
            if let askForLocation, !usingGPS, plan != nil || failed {
                Button {
                    Task { if await askForLocation() { refreshCount += 1 } }
                } label: {
                    Label("Use my location for an exact time", systemImage: "location")
                        .font(Theme.body(14, .semibold))
                        .foregroundStyle(Theme.accentText)
                }
                .buttonStyle(.plain)
            }
            if let plan, !plan.isTimeToGo {
                Toggle("Remind me when it’s time to leave", isOn: $remind)
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.text)
                    .tint(Theme.saffron)
            }
        }
        .padding(14)
        .card()
        .accessibilityElement(children: .combine)
        // Recalculate when the place or time changes (and each time you open it).
        .task(id: "\(winner.id)|\(meetTime.timeIntervalSince1970)|\(refreshCount)") { await refresh() }
        .onChange(of: remind) {
            LeaveBy.remindersOn = remind
            Task {
                if let plan { await LeaveBy.schedule(plan, sessionID: sessionID, winner: winner, title: title) }
            }
        }
    }

    private var headline: String {
        guard let plan else { return failed ? "No drive time yet" : "Working out when to leave…" }
        if plan.isTimeToGo {
            let late = plan.minutesLateIfLeavingNow
            return late > 0 ? "Leave now (about \(late) min late)" : "Time to leave!"
        }
        return "Leave by \(plan.leaveAt.formatted(date: .omitted, time: .shortened))"
    }

    private var detail: String {
        guard let plan else {
            if failed && !usingGPS && askForLocation != nil {
                return "Allow location to see when to leave."
            }
            return failed ? "Apple Maps couldn’t find a driving route. Use Directions for the trip." :
                "Using your location, which stays on this phone."
        }
        let from = "from \(originLabel)"
        var text = "\(plan.driveMinutes) min drive \(from), with 5 minutes to park."
        if !plan.isTimeToGo && remind { text += " We’ll remind you." }
        return text
    }

    private func refresh() async {
        failed = false
        guard let from = await origin() else {
            failed = true
            usingGPS = false
            return
        }
        usingGPS = from.isGPS
        originLabel = from.isGPS ? "where you are" : from.label
        let destination = CLLocationCoordinate2D(latitude: winner.latitude, longitude: winner.longitude)
        guard let next = await LeaveBy.plan(to: destination, meetTime: meetTime,
                                            from: from.coordinate, isGPS: from.isGPS) else {
            failed = true
            return
        }
        withAnimation(.snappy) { plan = next }
        await LeaveBy.schedule(next, sessionID: sessionID, winner: winner, title: title)
    }
}
