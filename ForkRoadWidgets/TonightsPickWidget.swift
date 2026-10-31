import SwiftUI
import WidgetKit
import AppIntents
import PickerCore

// MARK: - Timeline

struct PickEntry: TimelineEntry {
    let date: Date
    let pick: WidgetPick.Result?
}

struct TonightsPickProvider: TimelineProvider {
    func placeholder(in context: Context) -> PickEntry {
        PickEntry(date: Date(), pick: .init(place: Self.sample, source: .favorites))
    }

    func getSnapshot(in context: Context, completion: @escaping (PickEntry) -> Void) {
        let now = Date()
        let pick = WidgetPick.pick(at: now)
        // The widget gallery shows a sample when nothing is cached yet.
        if pick == nil && context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(PickEntry(date: now, pick: pick))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PickEntry>) -> Void) {
        let now = Date()
        var entries = [PickEntry(date: now, pick: WidgetPick.pick(at: now))]
        // A fresh pick every 3 hours, laid out for the next day.
        var next = WidgetPick.nextSlotStart(after: now)
        for _ in 0..<8 {
            entries.append(PickEntry(date: next, pick: WidgetPick.pick(at: next)))
            next = next.addingTimeInterval(WidgetPick.slotLength)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static let sample = Place(
        name: "Sora Ramen Bar", category: "Japanese",
        latitude: 38.0, longitude: -84.5, distanceMeters: 0.7 * Place.metersPerMile
    )
}

// MARK: - Widget

struct TonightsPickWidget: Widget {
    let kind = "TonightsPickWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TonightsPickProvider()) { entry in
            TonightsPickView(entry: entry)
                .containerBackground(for: .widget) { Theme.night }
                .widgetURL(URL(string: "forkroad://spin"))
        }
        .configurationDisplayName("Your Pick")
        .description("A random place from your Favorites, Want to try, or nearby list.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Views

struct TonightsPickView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PickEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // Small: label, name, category, Spin again.
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            if let pick = entry.pick {
                Text(pick.place.name)
                    .font(Theme.display(18))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(pick.place.category)
                    .font(Theme.body(12, .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                spinButton(compact: true)
            } else {
                emptyText
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // Medium: monogram tile + details on the left, Spin again on the right.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Spacer(minLength: 0)
            if let pick = entry.pick {
                HStack(spacing: 12) {
                    MonogramTile(name: pick.place.name, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pick.place.name)
                            .font(Theme.display(22))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                        Text("\(pick.place.category) · \(pick.source.label)")
                            .font(Theme.body(13, .medium))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    spinButton(compact: false)
                }
            } else {
                emptyText
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // Lock Screen: system-tinted text only (no button; tapping opens the Spin tab).
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("YOUR PICK")
                .font(.system(size: 11, weight: .bold))
                .widgetAccentable()
            if let pick = entry.pick {
                Text(pick.place.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(pick.place.category)
                    .font(.caption)
                    .lineLimit(1)
            } else {
                Text("Open ForkRoad to find places near you")
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        Text("FORKROAD · YOUR PICK")
            .font(Theme.body(10, .bold))
            .tracking(0.8)
            .foregroundStyle(Theme.accentText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var emptyText: some View {
        Text("Open ForkRoad to find places near you")
            .font(Theme.body(14, .semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(3)
            .minimumScaleFactor(0.8)
    }

    private func spinButton(compact: Bool) -> some View {
        Button(intent: SpinAgainIntent()) {
            Label("Spin again", systemImage: "sparkles")
                .font(Theme.body(compact ? 12 : 13, .bold))
                .foregroundStyle(Theme.onSaffron)
                .lineLimit(1)
                .padding(.horizontal, compact ? 10 : 14)
                .frame(height: compact ? 28 : 32)
                .background(Theme.saffron, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview(as: .systemSmall) {
    TonightsPickWidget()
} timeline: {
    PickEntry(date: .now, pick: .init(place: TonightsPickProvider.sample, source: .favorites))
    PickEntry(date: .now, pick: nil)
}
