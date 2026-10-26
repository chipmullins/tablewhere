import SwiftUI

/// Search radius slider with quick presets, from half a mile to 10 miles.
/// Bound to any value, so a sheet can have its own radius without changing Discover's.
struct RadiusSlider: View {
    @Binding var miles: Double
    var title = "Search radius"
    private let presets: [Double] = [1, 2, 5, 10]

    static func label(_ miles: Double) -> String {
        miles.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(miles)) mi"
            : String(format: "%.1f mi", miles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(Self.label(miles))
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.accentText)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: miles)
            }

            Slider(value: $miles, in: 0.5...10, step: 0.5)
                .tint(Theme.saffron)
                .accessibilityLabel(title)
                .accessibilityValue(Self.label(miles))

            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { preset in
                    let isOn = miles == preset
                    Button("\(Int(preset)) mi") { miles = preset }
                        .font(Theme.body(13, .semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(isOn ? Theme.night : Theme.text)
                        .background(isOn ? Theme.text : Theme.surfaceHigh,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .card(radius: 22)
        .sensoryFeedback(.selection, trigger: miles)
    }
}

/// The "No fast food" chip's look, bound to any Bool.
struct FastFoodChip: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label("No fast food", systemImage: isOn ? "checkmark" : "takeoutbag.and.cup.and.straw")
                .font(Theme.body(14, .semibold))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .foregroundStyle(isOn ? Theme.onSaffron : Theme.text)
                .background(isOn ? Theme.saffron : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }
}
