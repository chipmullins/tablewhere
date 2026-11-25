import SwiftUI

// The sleek layout's building blocks (1.2): big type, one primary action per
// screen, rounded 18–28 pt cards, fewer borders. Shared by the app, the
// iMessage app and the widgets (SwiftUI only, nothing app-specific).

/// The one big action on a screen: ink fill (or saffron), 60 pt tall.
struct SleekButtonStyle: ButtonStyle {
    enum Kind { case ink, saffron, plain }
    var kind: Kind = .ink
    var height: CGFloat = 60

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, kind: kind, height: height)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let kind: Kind
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            configuration.label
                .font(kind == .saffron ? Theme.display(17) : Theme.body(17, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(foreground)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.button + 2, style: .continuous))
                .overlay {
                    if kind == .plain {
                        RoundedRectangle(cornerRadius: Theme.Radius.button + 2, style: .continuous)
                            .strokeBorder(Theme.hairline)
                    }
                }
                .opacity(isEnabled ? 1 : 0.45)
                .modifier(PressEffect(isPressed: configuration.isPressed))
        }

        private var foreground: Color {
            switch kind {
            case .ink: return colorScheme == .dark ? Theme.onSaffron : Theme.onInk
            case .saffron: return Theme.onSaffron
            case .plain: return Theme.text
            }
        }

        private var background: Color {
            switch kind {
            // In dark mode the ink button would vanish, so it turns saffron.
            case .ink: return colorScheme == .dark ? Theme.saffron : Theme.ink
            case .saffron: return Theme.saffron
            case .plain: return Theme.surface
            }
        }
    }
}

private struct PressEffect: ViewModifier {
    let isPressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .contentShape(.interaction, Rectangle())
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isPressed ? 0.85 : 1)
            .animation(Motion.quick, value: isPressed)
    }
}

extension ButtonStyle where Self == SleekButtonStyle {
    /// The screen's primary action (ink in light mode, saffron in dark).
    static var sleekPrimary: SleekButtonStyle { SleekButtonStyle(kind: .ink) }
    static var sleekSaffron: SleekButtonStyle { SleekButtonStyle(kind: .saffron) }
    /// A secondary action next to a primary one.
    static var sleekPlain: SleekButtonStyle { SleekButtonStyle(kind: .plain) }
    static func sleek(_ kind: SleekButtonStyle.Kind, height: CGFloat = 60) -> SleekButtonStyle {
        SleekButtonStyle(kind: kind, height: height)
    }
}

/// A square, icon-only action (Call, Favorite, Try, Blacklist). Always has a
/// VoiceOver label; pass `isOn` for toggles so VoiceOver reads the state.
struct IconAction: View {
    let label: String
    let systemImage: String
    var isOn: Bool? = nil
    var tint: Color = Theme.text
    var size: CGFloat = 56
    var haptic: SensoryFeedback? = nil
    var hint: String? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var taps = 0

    var body: some View {
        let on = isOn == true
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(on ? Theme.onSaffron : tint)
                .frame(width: size, height: size)
                .background(on ? Theme.saffron : Theme.surface,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(on ? .clear : Theme.hairline))
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityValue(isOn == nil ? "" : (on ? "On" : "Off"))
        .sensoryFeedback(trigger: taps) { _, _ in haptic }
    }
}

/// A round icon button on a card or over a map (Share, Settings, Close).
struct RoundIconButton: View {
    let label: String
    let systemImage: String
    var size: CGFloat = 40
    var background: Color = Theme.surface
    var bordered = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundIconLabel(systemImage: systemImage, size: size, background: background, bordered: bordered)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
        .frame(minWidth: 44, minHeight: 44)
    }
}

/// The look of `RoundIconButton`, for ShareLink and Menu labels.
struct RoundIconLabel: View {
    let systemImage: String
    var size: CGFloat = 40
    var background: Color = Theme.surface
    var bordered = true

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(width: size, height: size)
            .background(background, in: Circle())
            .overlay { if bordered { Circle().strokeBorder(Theme.hairline) } }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
    }
}

/// A pill segmented control: a soft track with a white thumb. Used for
/// Eat out / Eat in, Spin's sources, and the Lists tabs.
struct SleekSegmented<Value: Hashable>: View {
    let title: String
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var height: CGFloat = 40
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isOn = option.value == selection
                Button {
                    withAnimation(Motion.quick) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(Theme.body(14, isOn ? .bold : .semibold))
                        .foregroundStyle(isOn ? Theme.text : Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.segmentThumb)
                                    .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sensoryFeedback(Haptic.tick, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A white pill that floats over a map or a hero (location, filters).
struct FloatingPill<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(Theme.body(14, .semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Theme.floating, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 9, y: 6)
    }
}

/// A tappable row card: tinted icon tile, title, subtitle, chevron
/// ("Make it a group plan").
struct SleekRow: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 44, height: 44)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(15, .bold))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button + 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button + 2, style: .continuous).strokeBorder(Theme.hairline))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A big screen title in Outfit, with an optional eyebrow above it.
struct ScreenTitle: View {
    let title: String
    var eyebrow: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow { SectionLabel(text: eyebrow) }
            Text(title)
                .font(Theme.display(34))
                .tracking(-0.8)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// A colored tile with the place's first letter (Discover rows, map pins).
struct InitialTile: View {
    let name: String
    var size: CGFloat = 52

    var body: some View {
        let colors = Theme.tileColors(for: name)
        Text(Self.initial(of: name))
            .font(.custom("Outfit-ExtraBold", size: size * 0.42, relativeTo: .title3))
            .foregroundStyle(colors.ink)
            .frame(width: size, height: size)
            .background(colors.background, in: RoundedRectangle(cornerRadius: size * 0.31, style: .continuous))
            .accessibilityHidden(true)
    }

    static func initial(of name: String) -> String {
        // Skip a leading "The" so "The Local Taco" gets an L.
        var words = name.split(separator: " ")
        if words.count > 1, words.first?.lowercased() == "the" { words.removeFirst() }
        return words.first?.first.map { String($0).uppercased() } ?? "?"
    }
}

/// Overlapping round avatars with initials ("S C J Y").
struct AvatarStack: View {
    let names: [String]
    var size: CGFloat = 36
    var ring: Color = Theme.ink
    var limit = 4

    var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach(Array(names.prefix(limit).enumerated()), id: \.offset) { _, name in
                PersonDot(name: name, size: size)
                    .overlay(Circle().strokeBorder(ring, lineWidth: 3))
            }
            if names.count > limit {
                Text("+\(names.count - limit)")
                    .font(Theme.body(size * 0.34, .bold))
                    .foregroundStyle(Theme.onInk)
                    .frame(width: size, height: size)
                    .background(Theme.trackFill, in: Circle())
                    .overlay(Circle().strokeBorder(ring, lineWidth: 3))
            }
        }
        .accessibilityHidden(true)
    }
}

/// One person's round initial, in a color picked from their name.
struct PersonDot: View {
    let name: String
    var size: CGFloat = 34

    var body: some View {
        Text(Self.initials(name))
            .font(.custom("Outfit-ExtraBold", size: size * 0.4, relativeTo: .body))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.color(for: name), in: Circle())
            .accessibilityHidden(true)
    }

    static func initials(_ name: String) -> String {
        name.split(separator: " ").first?.first.map { String($0).uppercased() } ?? "?"
    }

    /// Strong colors with white text (4.5:1 or better).
    static func color(for name: String) -> Color {
        let palette: [UInt32] = [0x2E7D4F, 0x4A5BD9, 0xB5521B, 0x8A3FA0, 0x257070, 0xA33A55, 0x5C6470]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return Color(hex: palette[hash % palette.count])
    }
}

/// A thin rounded progress bar.
struct SleekProgressBar: View {
    let value: Double
    var tint: Color = Theme.saffron
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.segmentTrack)
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The grabber at the top of a bottom sheet drawn in the page (not a system sheet).
struct SheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(Theme.muted.opacity(0.3))
            .frame(width: 40, height: 5)
            .accessibilityHidden(true)
    }
}
