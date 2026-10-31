import SwiftUI
import UIKit
import PickerCore

/// Lets the group's creator pick any meeting time (in 5-minute steps).
/// A time earlier than now means tomorrow. Used by the app and the iMessage
/// app (Shared/GroupUI isn't compiled into the widget).
struct MeetTimePickerSheet: View {
    let initial: Date
    var onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    init(initial: Date, onPick: @escaping (Date) -> Void) {
        self.initial = initial
        self.onPick = onPick
        _time = State(initialValue: initial)
    }

    /// The picked clock time as a real date (today, or tomorrow if it's passed).
    private var resolved: Date {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return MeetTimes.resolve(hour: parts.hour ?? 19, minute: parts.minute ?? 0)
    }

    private var isTomorrow: Bool { !Calendar.current.isDateInToday(resolved) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TimeWheel(date: $time, minuteInterval: 5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 216)
                if isTomorrow {
                    Label("That time has passed today, so it’s set for tomorrow.", systemImage: "moon.stars")
                        .font(Theme.body(13, .medium))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Button {
                    onPick(resolved)
                    dismiss()
                } label: {
                    Text("Meet at \(resolved.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.display(17))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Theme.night)
            .navigationTitle("Pick a time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.height(400)])
        .presentationBackground(Theme.night)
    }
}

/// UIKit's time wheel, because SwiftUI's DatePicker can't step by 5 minutes.
private struct TimeWheel: UIViewRepresentable {
    @Binding var date: Date
    var minuteInterval: Int

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = minuteInterval
        picker.date = date
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        if abs(picker.date.timeIntervalSince(date)) > 1 { picker.date = date }
    }

    func makeCoordinator() -> Coordinator { Coordinator(date: $date) }

    final class Coordinator: NSObject {
        let date: Binding<Date>
        init(date: Binding<Date>) { self.date = date }
        @objc func changed(_ picker: UIDatePicker) { date.wrappedValue = picker.date }
    }
}
