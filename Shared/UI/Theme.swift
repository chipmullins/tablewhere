import SwiftUI
import UIKit

/// ForkRoad's colors and type. Every color adapts to light and dark mode;
/// dark (night + saffron) is the signature look.
enum Theme {
    static let night = Color(light: 0xF6F5F1, dark: 0x0B0B0F)        // app background
    static let surface = Color(light: 0xFFFFFF, dark: 0x16161D)      // cards
    static let surfaceHigh = Color(light: 0xEFEDE8, dark: 0x1F1F29)  // buttons on cards
    static let hairline = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.07)
    static let text = Color(light: 0x15171A, dark: 0xF5F3EE)
    static let muted = Color(light: 0x5C5F66, dark: 0xA19FAA)        // 4.5:1+ on both backgrounds
    /// Saffron for fills (buttons, chips, the spin button). Same in both modes.
    static let saffron = Color(hex: 0xFFB23F)
    static let onSaffron = Color(hex: 0x1B1306)                      // text on saffron
    /// Saffron for text and icons on the background: darker in light mode so it stays readable.
    static let accentText = Color(light: 0x9A5B00, dark: 0xFFB23F)
    /// The orange "where" in the Tablewhere wordmark: saffron on dark, a
    /// deeper orange on light so it doesn't wash out.
    static let brandOrange = Color(light: 0xEE8400, dark: 0xFFB23F)
    /// A faint saffron wash for highlighted cards.
    static let accentSoft = Color(light: 0xFFF1D9, dark: 0x1F1A10)
    /// Empty part of progress bars.
    static let track = Color(light: 0xE4E2DC, dark: 0x23232E)
    /// Filled part of a non-leading progress bar.
    static let trackFill = Color(light: 0xA9A6AE, dark: 0x5C5A66)
    static let open = Color(light: 0x1E7A4D, dark: 0x5ED39A)
    static let danger = Color(light: 0xB3261E, dark: 0xFF8A7A)
    /// Blue used for trips.
    static let trip = Color(light: 0x2457A6, dark: 0x8FB4FF)
    static let tripSoft = Color(light: 0xDCE8F7, dark: 0x1B2433)

    // Type: Outfit for headings, DM Sans for everything else (same pairing as
    // Glofly). Both are bundled from Google Fonts under the SIL Open Font License
    // (see Licenses/). Sizes scale with the user's Dynamic Type setting.

    /// Headings: Outfit ExtraBold for big titles, Bold for smaller ones.
    static func display(_ size: CGFloat) -> Font {
        .custom(size >= 26 ? "Outfit-ExtraBold" : "Outfit-Bold", size: size, relativeTo: .title)
    }

    /// Body and UI text in DM Sans.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "DMSans-Bold"
        case .semibold: name = "DMSans-SemiBold"
        case .medium: name = "DMSans-Medium"
        default: name = "DMSans-Regular"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    /// Codes like "K7Q·4MZ".
    static func code(_ size: CGFloat) -> Font {
        .custom("Outfit-Bold", size: size, relativeTo: .body)
    }

    /// Applies the fonts to UIKit-drawn chrome (navigation bars, tab bar,
    /// segmented controls) so they match the SwiftUI screens.
    @MainActor
    static func applyUIKitAppearance() {
        func font(_ name: String, _ size: CGFloat) -> UIFont {
            UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .semibold)
        }
        let nav = UINavigationBar.appearance()
        nav.titleTextAttributes = [.font: font("Outfit-Bold", 17), .foregroundColor: UIColor(text)]
        nav.largeTitleTextAttributes = [.font: font("Outfit-ExtraBold", 32), .foregroundColor: UIColor(text)]

        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes([.font: font("DMSans-SemiBold", 13)], for: .normal)
        segmented.setTitleTextAttributes([.font: font("DMSans-Bold", 13)], for: .selected)

        UITabBarItem.appearance().setTitleTextAttributes([.font: font("DMSans-Medium", 10)], for: .normal)
    }

    /// Tile colors, picked by a stable hash of the name so a restaurant
    /// always gets the same tile.
    static func tileColors(for name: String) -> (background: Color, ink: Color) {
        // (dark background, dark ink, light background, light ink)
        let palette: [(UInt32, UInt32, UInt32, UInt32)] = [
            (0x3A2914, 0xFFB23F, 0xFCE9D2, 0x8A4A0B), (0x3A1A1A, 0xFF8A7A, 0xFBE1DE, 0x9A2B1E),
            (0x3A1620, 0xFF7A93, 0xFADDE5, 0x93203F), (0x1D2A1A, 0x9BE08A, 0xDDEFD8, 0x2F6A22),
            (0x332A10, 0xFFD25E, 0xF7ECC2, 0x6E5508), (0x2A2233, 0xD7B8FF, 0xECE3F7, 0x5B3A8C),
            (0x1B2433, 0x8FB4FF, 0xDCE8F7, 0x1F4E8C)
        ]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        let p = palette[hash % palette.count]
        return (Color(light: p.2, dark: p.0), Color(light: p.3, dark: p.1))
    }
}

/// Which appearance the user picked in Settings.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension Color {
    /// A color that switches between light and dark mode automatically.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
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
