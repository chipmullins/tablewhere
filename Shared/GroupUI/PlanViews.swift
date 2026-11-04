import SwiftUI
import PickerCore

// "I'll pick" plans: the creator already knows where and when. These views
// are shared by the app and the iMessage app (Shared/GroupUI isn't compiled
// into the widget).

/// Who's coming to a plan, and (for everyone but the creator) I'm in / Can't
/// make it, with a guest count when you're in.
struct RSVPPanel: View {
    let session: GroupSession
    let count: RSVPCount
    let mine: GroupRSVP?
    let isOwner: Bool
    let isWorking: Bool
    /// In the group but haven't answered (shown to the creator only).
    var noReply: [String] = []
    /// Going, guests.
    var onAnswer: (Bool, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Who’s coming")
            Text(count.summary)
                .font(Theme.display(22))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            deadline

            if !isOwner && session.rsvpOpen {
                answerButtons
                if mine?.going == true { guestStepper }
            } else if !isOwner, let mine {
                Label(mine.going ? "You said you’re in\(guestsText(mine.guests))" : "You said you can’t make it",
                      systemImage: mine.going ? "checkmark.circle.fill" : "xmark.circle")
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.muted)
            }

            if !count.going.isEmpty {
                names("Coming", count.going.map { $0.name + ($0.guests > 0 ? " +\($0.guests)" : "") })
            }
            if !count.notGoing.isEmpty {
                names("Can’t make it", count.notGoing.map(\.name))
            }
            if isOwner && !noReply.isEmpty {
                names("No reply yet", noReply)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 22)
    }

    @ViewBuilder
    private var deadline: some View {
        if let by = session.rsvpBy {
            Label(session.rsvpOpen ? "Reply by \(MeetTimes.label(for: by))" : "Replies are closed",
                  systemImage: session.rsvpOpen ? "clock" : "lock.fill")
                .font(Theme.body(13, .semibold))
                .foregroundStyle(session.rsvpOpen ? Theme.accentText : Theme.muted)
        }
    }

    private var answerButtons: some View {
        HStack(spacing: 8) {
            answerButton("I’m in", systemImage: "hand.thumbsup.fill", isOn: mine?.going == true) {
                onAnswer(true, mine?.guests ?? 0)
            }
            answerButton("Can’t make it", systemImage: "hand.raised", isOn: mine?.going == false) {
                onAnswer(false, 0)
            }
        }
        .disabled(isWorking)
    }

    private func answerButton(_ title: String, systemImage: String, isOn: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Theme.body(15, .bold))
                .foregroundStyle(isOn ? Theme.onSaffron : Theme.text)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(isOn ? Theme.saffron : Theme.surfaceHigh,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(Haptic.tick, trigger: isOn)
    }

    private var guestStepper: some View {
        let guests = mine?.guests ?? 0
        return HStack {
            Text(guests == 0 ? "Just me" : "Bringing \(guests) guest\(guests == 1 ? "" : "s")")
                .font(Theme.body(15, .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            Stepper("Guests", value: Binding(get: { guests },
                                             set: { onAnswer(true, $0) }),
                    in: 0...GroupRSVP.maxGuests)
                .labelsHidden()
                .disabled(isWorking)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func names(_ title: String, _ list: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(Theme.body(11, .heavy))
                .tracking(1)
                .foregroundStyle(Theme.muted)
            Text(list.joined(separator: ", "))
                .font(Theme.body(14, .medium))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func guestsText(_ guests: Int) -> String {
        guests == 0 ? "" : " (+\(guests))"
    }
}

/// The "I'll pick" setup rows for a Form: when, a note, and whether to ask
/// who's coming (off by default), with an optional reply-by time.
struct PlanSetupRows: View {
    @Binding var meetTime: Date
    @Binding var note: String
    @Binding var asksRSVP: Bool
    @Binding var hasReplyBy: Bool
    @Binding var replyBy: Date

    var body: some View {
        Section {
            DatePicker("Date & time", selection: $meetTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
            TextField("Note (optional), like “Bring a gift!”", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .onChange(of: note) { _, newValue in
                    if newValue.contains("\n") { note = newValue.replacingOccurrences(of: "\n", with: "") }
                    if note.count > GroupSession.maxNoteLength { note = String(note.prefix(GroupSession.maxNoteLength)) }
                }
        } header: {
            Text("When")
        }
        .listRowBackground(Theme.surface)

        Section {
            Toggle("Ask who’s coming", isOn: $asksRSVP.animation())
                .tint(Theme.saffron)
            if asksRSVP {
                Toggle("Set a reply-by time", isOn: $hasReplyBy.animation())
                    .tint(Theme.saffron)
                if hasReplyBy {
                    // max(): a ClosedRange with its ends swapped would crash.
                    DatePicker("Reply by", selection: $replyBy, in: Date()...max(meetTime, Date()),
                               displayedComponents: [.date, .hourAndMinute])
                }
            }
        } footer: {
            Text(asksRSVP
                 ? "Everyone can tap I’m in (with guests) or Can’t make it, and you’ll see the headcount for the reservation."
                 : "Just sends the plan. Turn this on if you need a headcount.")
        }
        .listRowBackground(Theme.surface)
        // A reply-by after dinner makes no sense: keep it before.
        .onChange(of: meetTime) { _, newValue in
            if replyBy > newValue { replyBy = newValue.addingTimeInterval(-60 * 60) }
        }
        // Turning it on starts from a sensible time for the date you set.
        .onChange(of: hasReplyBy) { _, on in
            if on { replyBy = Self.defaultReplyBy(for: meetTime) }
        }
    }

    /// A sensible starting time: tomorrow at 7 PM.
    static func defaultMeetTime(now: Date = .now) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 19, minute: 0, second: 0, of: tomorrow) ?? now
    }

    /// What to save: before the meal, and at least a few minutes from now
    /// (a picker left open can drift into the past).
    static func clampedReplyBy(_ replyBy: Date, meetTime: Date, now: Date = .now) -> Date {
        max(min(replyBy, meetTime), min(now.addingTimeInterval(5 * 60), meetTime))
    }

    /// The reply-by default: the day before at noon, or an hour before if that's sooner.
    static func defaultReplyBy(for meetTime: Date, now: Date = .now) -> Date {
        let calendar = Calendar.current
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: meetTime)
            .flatMap { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) }
        if let dayBefore, dayBefore.timeIntervalSince(now) > 0 { return dayBefore }
        return clampedReplyBy(meetTime.addingTimeInterval(-60 * 60), meetTime: meetTime, now: now)
    }
}

/// The creator changes a plan's date and time (any day, not just today).
struct PlanTimeSheet: View {
    let initial: Date
    var onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    init(initial: Date, onPick: @escaping (Date) -> Void) {
        self.initial = initial
        self.onPick = onPick
        _time = State(initialValue: max(initial, Date()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker("Date & time", selection: $time, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .tint(Theme.saffron)
                Spacer(minLength: 0)
                Button {
                    onPick(time)
                    dismiss()
                } label: {
                    Text("Meet \(MeetTimes.phrase(for: time))")
                        .font(Theme.display(17))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Theme.night)
            .navigationTitle("Change the time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.night)
    }
}
