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
                        .buttonStyle(.pressable)
                }
            }
        }
        .padding(16)
        .card(radius: 22)
        .sensoryFeedback(.selection, trigger: miles)
    }
}

/// One "Filters" chip for the place-type filters (No fast food, No coffee &
/// sweets), so the chip row starts with the cuisines. Lit, with a count,
/// when any are on.
struct FoodFiltersChip: View {
    @Binding var noFastFood: Bool
    @Binding var noCoffeeSweets: Bool

    private var count: Int { (noFastFood ? 1 : 0) + (noCoffeeSweets ? 1 : 0) }

    var body: some View {
        Menu {
            Toggle(isOn: $noFastFood) {
                Label("No fast food", systemImage: "takeoutbag.and.cup.and.straw")
            }
            Toggle(isOn: $noCoffeeSweets) {
                Label("No coffee & sweets", systemImage: "cup.and.saucer")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                Text("Filters")
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.body(12, .bold))
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Theme.onSaffron.opacity(0.15), in: Circle())
                }
            }
            .font(Theme.body(14, .semibold))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .foregroundStyle(count > 0 ? Theme.onSaffron : Theme.text)
            .background(count > 0 ? Theme.saffron : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(count > 0 ? .clear : Theme.hairline))
        }
        .accessibilityLabel(accessibilityText)
        .sensoryFeedback(.selection, trigger: count)
    }

    private var accessibilityText: String {
        var on: [String] = []
        if noFastFood { on.append("no fast food") }
        if noCoffeeSweets { on.append("no coffee and sweets") }
        return on.isEmpty ? "Filters, none on" : "Filters: " + on.joined(separator: ", ")
    }
}

/// The "No fast food" chip's look, bound to any Bool.
struct FastFoodChip: View {
    @Binding var isOn: Bool
    var title = "No fast food"
    var icon = "takeoutbag.and.cup.and.straw"

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(title, systemImage: isOn ? "checkmark" : icon)
                .font(Theme.body(14, .semibold))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .foregroundStyle(isOn ? Theme.onSaffron : Theme.text)
                .background(isOn ? Theme.saffron : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.hairline))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }
}
