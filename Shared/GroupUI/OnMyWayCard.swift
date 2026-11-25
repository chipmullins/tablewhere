import SwiftUI
import CoreLocation
import PickerCore

/// "On my way" on a decided plan with a meet time (app lobby and iMessage):
/// who's on the way and when they'll get there ("Sam ~7:05 · Alex ~7:12 ·
/// Jo hasn't left"), and your buttons: I'm on my way, Running late, I'm
/// here, Stop sharing. Arrival times only, never locations.
struct OnMyWayCard: View {
    let sessionID: String
    let winner: GroupOption
    let meetTime: Date
    let line: String?
    let mine: GroupETA?
    /// The app keeps your time fresh as you drive; iMessage shares it once.
    var updatesLive: Bool = false
    /// Everyone's shared times and the group (1.2): one row each with a
    /// progress bar. Without them the card shows just the summary line.
    var etas: [GroupETA] = []
    var members: [GroupMember] = []

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var taps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("On the way")
                    .font(Theme.display(18))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if isWorking {
                    ProgressView()
                } else {
                    Text("Times only, never locations")
                        .font(Theme.body(12, .medium))
                        .foregroundStyle(Theme.muted)
                }
            }

            if members.isEmpty {
                Text(line ?? "Nobody’s left yet")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 14) {
                        ForEach(rows) { row in personRow(row, now: context.date) }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line ?? "Nobody’s left yet")
            }

            buttons

            Text(footnote)
                .font(Theme.body(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.body(12, .semibold))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(18)
        .card(radius: Theme.Radius.card + 2)
        .sensoryFeedback(Haptic.commit, trigger: taps)
    }

    // MARK: People

    private struct Row: Identifiable {
        let id: String
        let name: String
        let eta: GroupETA?
    }

    /// Everyone in the group (you last, like the plan), plus anyone sharing a
    /// time who isn't in the member list yet.
    private var rows: [Row] {
        let me = GroupService.shared.currentUserID
        var list = members.map { member in
            Row(id: member.id, name: member.id == me ? "You" : member.name,
                eta: etas.first { $0.userID == member.id })
        }
        for eta in etas where !members.contains(where: { $0.id == eta.userID }) {
            list.append(Row(id: eta.userID, name: eta.userID == me ? "You" : eta.name, eta: eta))
        }
        return list.sorted { a, b in (a.name == "You" ? 1 : 0) < (b.name == "You" ? 1 : 0) }
    }

    private func personRow(_ row: Row, now: Date) -> some View {
        let tint = PersonDot.color(for: row.name == "You" ? (Identity.displayName ?? "You") : row.name)
        return HStack(spacing: 12) {
            PersonDot(name: row.name == "You" ? (Identity.displayName ?? "You") : row.name)
            VStack(spacing: 6) {
                HStack {
                    Text(row.name).font(Theme.body(14, .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(status(row.eta))
                        .font(Theme.body(13, .semibold))
                        .foregroundStyle(row.eta?.status == .late ? Theme.accentText : Theme.muted)
                }
                SleekProgressBar(value: progress(row.eta, now: now), tint: tint)
            }
        }
    }

    /// "Here", "~7:20", "10 late", "Will text", "Not left".
    private func status(_ eta: GroupETA?) -> String {
        guard let eta else { return "Not left" }
        switch eta.status {
        case .arrived: return "Here"
        case .late:
            if let minutes = eta.lateMinutes { return "\(minutes) late" }
            if let time = eta.eta { return "Late, ~\(Self.time(time))" }
            return "Will text"
        case .onTheWay:
            return eta.eta.map { "~\(Self.time($0))" } ?? "On the way"
        }
    }

    /// How far along the drive is: from when they left to when they'll get there.
    private func progress(_ eta: GroupETA?, now: Date) -> Double {
        guard let eta else { return 0 }
        if eta.status == .arrived { return 1 }
        guard let arrive = eta.eta, let left = eta.leftAt, arrive > left else {
            return eta.status == .late ? 0.3 : 0.5
        }
        let done = now.timeIntervalSince(left) / arrive.timeIntervalSince(left)
        return min(0.95, max(0.05, done))
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
            .replacingOccurrences(of: " AM", with: "")
            .replacingOccurrences(of: " PM", with: "")
    }

    @ViewBuilder
    private var buttons: some View {
        switch mine?.status {
        case nil:
            // "I'm on my way" and "Late +10" side by side (hold Late for more choices).
            HStack(spacing: 10) {
                Button { act { _ = try await OnMyWay.start(sessionID: sessionID, destination: destination, meetTime: meetTime) } } label: {
                    Label("I’m on my way", systemImage: "car.fill")
                }
                .buttonStyle(SleekButtonStyle(kind: .saffron, height: 56))
                lateMenu(primaryMinutes: 10, title: "Late +10")
                    .fixedSize(horizontal: true, vertical: false)
            }
            .disabled(isWorking)
        case .onTheWay?, .late?:
            HStack(spacing: 10) {
                Button { act { try await OnMyWay.arrived(sessionID: sessionID) } } label: {
                    Label("I’m here", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(SleekButtonStyle(kind: .saffron, height: 56))
                lateMenu(primaryMinutes: nil, title: "Running late")
                    .fixedSize(horizontal: true, vertical: false)
            }
            .disabled(isWorking)
            Button("Stop sharing") { act { await OnMyWay.stop(sessionID: sessionID) } }
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 44)
                .disabled(isWorking)
        case .arrived?:
            Label("You’re here. Enjoy!", systemImage: "checkmark.seal.fill")
                .font(Theme.body(14, .semibold))
                .foregroundStyle(Theme.accentText)
        }
    }

    /// Running late: +10 / +15 / +30, or "I'll text you". With `primaryMinutes`
    /// a tap sends that right away and a long press shows the rest.
    @ViewBuilder
    private func lateMenu(primaryMinutes: Int?, title: String) -> some View {
        let label = Text(title)
            .font(Theme.body(14, .bold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous).strokeBorder(Theme.hairline))
        let choices = Group {
            ForEach(GroupETA.lateChoices, id: \.self) { minutes in
                Button("About \(minutes) min late") {
                    act { try await OnMyWay.runningLate(sessionID: sessionID, minutes: minutes, meetTime: meetTime) }
                }
            }
            Button("I’ll text you") {
                act { try await OnMyWay.runningLate(sessionID: sessionID, minutes: nil, meetTime: meetTime) }
            }
        }
        if let primaryMinutes {
            Menu {
                choices
            } label: {
                label
            } primaryAction: {
                act { try await OnMyWay.runningLate(sessionID: sessionID, minutes: primaryMinutes, meetTime: meetTime) }
            }
            .accessibilityLabel("Running late, \(primaryMinutes) minutes")
            .accessibilityHint("Touch and hold for other choices")
        } else {
            Menu { choices } label: { label }
                .accessibilityLabel("Running late")
        }
    }

    private var footnote: String {
        if mine?.status == .arrived { return "Your arrival time is deleted after the plan." }
        return updatesLive
            ? "Shares when you’ll get there, never where you are. Updates as you drive until you arrive."
            : "Shares when you’ll get there, never where you are."
    }

    private var destination: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: winner.latitude, longitude: winner.longitude)
    }

    private func act(_ work: @escaping () async throws -> Void) {
        taps += 1
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do { try await work() }
            catch { errorMessage = GroupService.message(for: error) }
        }
    }
}
