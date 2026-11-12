import SwiftUI

/// Tablespin's motion vocabulary, so sheets, cards and results all move the
/// same way.
enum Motion {
    /// Cards, results, rows appearing and changing.
    static let standard: Animation = .snappy(duration: 0.32)
    /// Small state flips: a chip, a check, a pressed button.
    static let quick: Animation = .snappy(duration: 0.18)
    /// A result arriving: a little settle, never a wobble.
    static let reveal: Animation = .spring(duration: 0.45, bounce: 0.18)
}

/// A button that visibly presses: shrinks a touch and dims while your finger
/// is down, so every tap answers instantly. With Reduce Motion on it only dims.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, scale: scale)
    }

    private struct PressableBody: View {
        let configuration: Configuration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed && !reduceMotion && isEnabled ? scale : 1)
                .opacity(configuration.isPressed && isEnabled ? 0.82 : 1)
                .animation(Motion.quick, value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PressableStyle {
    /// Tablespin's default tappable look (see `PressableStyle`).
    static var pressable: PressableStyle { PressableStyle() }
}
