import SwiftUI
import PickerCore

/// The colored letter tile that stands in for a photo (MapKit has no photos).
struct MonogramTile: View {
    let name: String
    var size: CGFloat = 60

    var body: some View {
        let colors = Theme.tileColors(for: name)
        Text(String(name.prefix(1)).uppercased())
            .font(Theme.display(size * 0.43))
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
            MonogramTile(name: place.name)
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(place.category) · \(place.distanceLabel)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted.opacity(0.6))
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
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 40)
                .foregroundStyle(isSelected ? Theme.night : Theme.text)
                .background(isSelected ? Theme.text : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? .clear : Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Square icon + label button used for Call / Go / Save / Block.
struct ActionTile: View {
    let title: String
    let systemImage: String
    var tint: Color = Theme.text
    var background: Color = Theme.surfaceHigh
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 19, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Small uppercase section label.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.muted
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(1)
            .foregroundStyle(color)
    }
}
