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

/// One restaurant in a list.
struct PlaceRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: 14) {
            MonogramTile(name: place.name, category: place.category)
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(Theme.body(16, .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(place.category) · \(place.distanceLabel)")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(Theme.body(14, .semibold))
                .foregroundStyle(Theme.muted.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(12)
        .card()
        .contentShape(Rectangle())
    }
}

/// A pill-shaped selectable chip.
struct Chip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.body(14, .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(minHeight: 40)
                .foregroundStyle(isSelected ? Theme.night : Theme.text)
                .background(isSelected ? Theme.text : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? .clear : Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Square icon + label button used for Call / Go / Save / Block.
/// Pass `isOn` when the tile is a toggle (Favorite, Try) so VoiceOver reads
/// its state; leave it nil for plain actions.
struct ActionTile: View {
    let title: String
    let systemImage: String
    var tint: Color = Theme.text
    var background: Color = Theme.surfaceHigh
    var isOn: Bool? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let button = Button(action: action) {
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
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)

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

/// A shimmering stand-in for a restaurant row while results load.
struct PlaceRowPlaceholder: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surfaceHigh)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Theme.surfaceHigh).frame(width: 160, height: 12)
                Capsule().fill(Theme.surfaceHigh).frame(width: 100, height: 10)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .card()
        .shimmering()
        .accessibilityHidden(true)
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
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .card(radius: 22)
    }
}

/// A soft light sweep across a placeholder. Still when Reduce Motion is on.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, Color.white.opacity(0.10), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: phase * geo.size.width * 1.4)
                    }
                    .allowsHitTesting(false)
                    .clipped()
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}
