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

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var taps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "car.fill")
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 34, height: 34)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("On my way")
                        .font(Theme.body(15, .semibold))
                        .foregroundStyle(Theme.text)
                    Text(line ?? "Nobody’s left yet")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isWorking { ProgressView() }
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
        .padding(14)
        .card()
        .sensoryFeedback(Haptic.commit, trigger: taps)
    }

    @ViewBuilder
    private var buttons: some View {
        switch mine?.status {
        case nil:
            Button { act { _ = try await OnMyWay.start(sessionID: sessionID, destination: destination, meetTime: meetTime) } } label: {
                Label("I’m on my way", systemImage: "car.fill")
                    .font(Theme.display(16))
                    .foregroundStyle(Theme.onSaffron)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.pressable)
            .disabled(isWorking)
        case .onTheWay?, .late?:
            HStack(spacing: 8) {
                Menu {
                    ForEach(GroupETA.lateChoices, id: \.self) { minutes in
                        Button("About \(minutes) min late") {
                            act { try await OnMyWay.runningLate(sessionID: sessionID, minutes: minutes, meetTime: meetTime) }
                        }
                    }
                    Button("I’ll text you") {
                        act { try await OnMyWay.runningLate(sessionID: sessionID, minutes: nil, meetTime: meetTime) }
                    }
                } label: {
                    smallButton("Running late", systemImage: "clock.badge.exclamationmark")
                }
                Button { act { try await OnMyWay.arrived(sessionID: sessionID) } } label: {
                    smallButton("I’m here", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.pressable)
            }
            .disabled(isWorking)
            Button("Stop sharing") { act { await OnMyWay.stop(sessionID: sessionID) } }
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.accentText)
                .disabled(isWorking)
        case .arrived?:
            Label("You’re here. Enjoy!", systemImage: "checkmark.seal.fill")
                .font(Theme.body(14, .semibold))
                .foregroundStyle(Theme.accentText)
        }
    }

    private func smallButton(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(Theme.body(14, .semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
