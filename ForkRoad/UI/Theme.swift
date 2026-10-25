import SwiftUI

/// ForkRoad's colors and type, matching the prototype (dark + saffron).
enum Theme {
    static let night = Color(hex: 0x0B0B0F)      // app background
    static let surface = Color(hex: 0x16161D)    // cards
    static let surfaceHigh = Color(hex: 0x1F1F29) // buttons on cards
    static let hairline = Color.white.opacity(0.07)
    static let text = Color(hex: 0xF5F3EE)
    static let muted = Color(hex: 0xA19FAA)
    static let saffron = Color(hex: 0xFFB23F)
    static let onSaffron = Color(hex: 0x1B1306)  // text on saffron
    static let open = Color(hex: 0x5ED39A)
    static let danger = Color(hex: 0xFF8A7A)

    /// Big headings. Rounded system font for now; swap in Bricolage Grotesque
    /// (free under the SIL Open Font License) once it's added to the bundle.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Monogram tile colors, picked by a stable hash of the name so a
    /// restaurant always gets the same tile.
    static func tileColors(for name: String) -> (background: Color, ink: Color) {
        let palette: [(UInt32, UInt32)] = [
            (0x3A2914, 0xFFB23F), (0x3A1A1A, 0xFF8A7A), (0x3A1620, 0xFF7A93),
            (0x1D2A1A, 0x9BE08A), (0x332A10, 0xFFD25E), (0x2A2233, 0xD7B8FF),
            (0x1B2433, 0x8FB4FF)
        ]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        let pair = palette[hash % palette.count]
        return (Color(hex: pair.0), Color(hex: pair.1))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The standard rounded card used across screens.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
    }
}

extension View {
    func card(radius: CGFloat = 20) -> some View { modifier(CardBackground(radius: radius)) }
}
