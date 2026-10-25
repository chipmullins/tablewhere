import SwiftUI

/// Search radius slider with quick presets, from half a mile to 10 miles.
struct RadiusControl: View {
    @Environment(AppModel.self) private var model
    private let presets: [Double] = [1, 2, 5, 10]

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Search radius")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(model.radiusLabel)
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.saffron)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: model.radiusMiles)
            }

            Slider(value: $model.radiusMiles, in: 0.5...10, step: 0.5)
                .tint(Theme.saffron)
                .accessibilityLabel("Search radius")
                .accessibilityValue(model.radiusLabel)

            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { miles in
                    let isOn = model.radiusMiles == miles
                    Button("\(Int(miles)) mi") { model.radiusMiles = miles }
                        .font(.system(size: 13, weight: .semibold))
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
        .sensoryFeedback(.selection, trigger: model.radiusMiles)
    }
}
