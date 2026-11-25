import SwiftUI
import PickerCore

/// A tinted tile with a cuisine icon (taco, ramen, pizza…) that stands in for a
/// photo, since MapKit has no photos. The icon is guessed from the category and
/// name; the tint is stable per restaurant.
struct MonogramTile: View {
    let name: String
    var category: String = ""
    var size: CGFloat = 60

    var body: some View {
        let colors = Theme.tileColors(for: name)
        let icon = CuisineIcon.guess(name: name, category: category)
        Image(icon.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.5, height: size * 0.5)
            .foregroundStyle(colors.ink)
            .frame(width: size, height: size)
            .background(colors.background, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One restaurant in a list (1.2): a colored initial tile, the name, what
/// and how far, on a clean row with a hairline under it.
struct PlaceRow: View {
    let place: Place
    var showsChevron = true
    var showsDivider = true

    var body: some View {
        HStack(spacing: 14) {
            InitialTile(name: place.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(Theme.body(16, .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(place.category) · \(place.distanceLabel)")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.muted.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
        .contentShape(Rectangle())
    }
}

/// A pill-shaped selectable chip. Ticks on tap; pass `haptic: nil` when the
/// owner plays its own feedback (CuisineChips does, so it can warn at the limit).
struct Chip: View {
    let label: String
    let isSelected: Bool
    var haptic: SensoryFeedback? = Haptic.tick
    let action: () -> Void

    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Text(label)
                .font(Theme.body(14, .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(minHeight: 40)
                .foregroundStyle(isSelected ? Theme.night : Theme.text)
                .background(isSelected ? Theme.text : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? .clear : Theme.hairline))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(trigger: taps) { _, _ in haptic }
    }
}

/// Square icon + label button used for Call / Go / Save / Block.
/// Pass `isOn` when the tile is a toggle (Favorite, Try) so VoiceOver reads
/// its state; leave it nil for plain actions. Pass a `haptic` from `Haptic`
/// (`.tick` for toggles, `.destructive` for Blacklist) to play it on tap.
struct ActionTile: View {
    let title: String
    let systemImage: String
    var tint: Color = Theme.text
    var background: Color = Theme.surfaceHigh
    var isOn: Bool? = nil
    var haptic: SensoryFeedback? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var taps = 0

    var body: some View {
        let button = Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(Theme.body(19, .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.body(12, .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(tint)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(trigger: taps) { _, _ in haptic }

        if let isOn {
            button
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityValue(isOn ? "On" : "Off")
        } else {
            button
        }
    }
}

/// Small uppercase section label.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.muted
    var body: some View {
        Text(text.uppercased())
            .font(Theme.body(12, .bold))
            .tracking(1)
            .foregroundStyle(color)
            // VoiceOver can spell short all-caps words letter by letter.
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A shimmering stand-in for a restaurant row (a `PlaceRow`) while results load.
/// Wrap a group of them in `.loadingSkeleton()` so VoiceOver hears one "Loading".
struct PlaceRowPlaceholder: View {
    var tileSize: CGFloat = 52

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: tileSize * 0.31, style: .continuous)
                .fill(Theme.surfaceHigh)
                .frame(width: tileSize, height: tileSize)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBar(width: 160, height: 12)
                SkeletonBar(width: 100, height: 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .shimmering()
    }
}

/// A stand-in for a plain list row (small tile, name, detail), for pickers in a `List`.
struct ListRowPlaceholder: View {
    var tileSize: CGFloat = 36

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: tileSize * 0.27, style: .continuous)
                .fill(Theme.surfaceHigh)
                .frame(width: tileSize, height: tileSize)
            VStack(alignment: .leading, spacing: 7) {
                SkeletonBar(width: 150, height: 11)
                SkeletonBar(width: 90, height: 9)
            }
            Spacer(minLength: 0)
        }
        .shimmering()
    }
}

/// One gray line of a skeleton.
struct SkeletonBar: View {
    let width: CGFloat
    var height: CGFloat = 12

    var body: some View {
        Capsule()
            .fill(Theme.surfaceHigh)
            .frame(width: width, height: height)
    }
}

/// A friendly message card for empty, offline, and permission states.
struct StateCard: View {
    let icon: String
    let title: String
    let message: String
    var action: (String, () -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 60, height: 60)
                .background(Theme.accentSoft, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.display(19))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Theme.body(14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if let action {
                Button(action: action.1) {
                    Text(action.0)
                        .font(Theme.body(15, .bold))
                        .foregroundStyle(Theme.onSaffron)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(Theme.saffron, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .card(radius: Theme.Radius.hero)
    }
}

/// A soft light sweep across a placeholder, clipped to its shapes. Still when
/// Reduce Motion is on.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, highlight, .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: phase * geo.size.width * 1.4)
                    }
                    .allowsHitTesting(false)
                    // Only over the placeholder's own shapes (rounded corners included).
                    .mask { content }
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }

    private var highlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.55)
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }

    /// A loading skeleton, read by VoiceOver as one "Loading" element. Pass
    /// `announces: false` for the rest of a skeleton split across list rows,
    /// so only the first row speaks.
    @ViewBuilder
    func loadingSkeleton(announces: Bool = true) -> some View {
        if announces {
            accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading")
        } else {
            accessibilityHidden(true)
        }
    }
}


/// The Tablewhere wordmark: "Table" in ink (cream on dark), "where" in orange.
struct Wordmark: View {
    var size: CGFloat = 18
    var tableColor: Color = Theme.text
    var whereColor: Color = Theme.brandOrange

    var body: some View {
        (Text("Table").foregroundColor(tableColor) + Text("where").foregroundColor(whereColor))
            .font(Theme.display(size))
            .tracking(-size * 0.02)
            .accessibilityLabel("Tablewhere")
    }
}
