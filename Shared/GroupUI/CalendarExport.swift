import SwiftUI
import EventKit
import CoreLocation
import PickerCore

/// Puts the plan on your calendar: the restaurant, the meeting time, the
/// address, and the note. Only asks to add events (it can't read your calendar).
@MainActor
enum CalendarExport {
    enum Failure: LocalizedError {
        case notAllowed
        var errorDescription: String? {
            "Tablespin can’t add to your calendar. Turn it on in Settings → Privacy & Security → Calendars."
        }
    }

    static func add(session: GroupSession, winner: GroupOption, meetTime: Date) async throws {
        let store = EKEventStore()
        guard try await store.requestWriteOnlyAccessToEvents() else { throw Failure.notAllowed }

        let event = EKEvent(eventStore: store)
        event.title = "\(winner.name) · \(session.title)"
        event.startDate = meetTime
        event.endDate = meetTime.addingTimeInterval(90 * 60)
        event.location = winner.address ?? winner.name
        let place = EKStructuredLocation(title: winner.name)
        place.geoLocation = CLLocation(latitude: winner.latitude, longitude: winner.longitude)
        event.structuredLocation = place
        var notes = ["Picked with Tablespin."]
        if let note = session.trimmedNote { notes.insert("Note from \(session.createdByName): \(note)", at: 0) }
        event.notes = notes.joined(separator: "\n")
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
    }
}

/// "Add to Calendar" → "Added to your calendar".
struct AddToCalendarButton: View {
    let session: GroupSession
    let winner: GroupOption
    let meetTime: Date

    @State private var added = false
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: add) {
                Label(added ? "Added to your calendar" : "Add to Calendar",
                      systemImage: added ? "checkmark.circle.fill" : "calendar.badge.plus")
                    .font(Theme.body(15, .bold))
                    .foregroundStyle(added ? Theme.muted : Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(added || working)
            if let errorMessage {
                Text(errorMessage).font(Theme.body(12)).foregroundStyle(Theme.danger)
            }
        }
        // A new time means it can be added again.
        .onChange(of: meetTime) { added = false }
    }

    private func add() {
        working = true
        errorMessage = nil
        Task {
            defer { working = false }
            do {
                try await CalendarExport.add(session: session, winner: winner, meetTime: meetTime)
                added = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
