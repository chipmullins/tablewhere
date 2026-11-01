import SwiftUI
import PickerCore

/// Multi-select cuisine chips. "All" clears the selection; tapping a cuisine
/// toggles it. Used on Discover, Spin, trips, group picks, and in iMessage.
///
/// `NoFastFoodChip` is supplied by each target: the app's reads AppModel,
/// the iMessage extension's reads the shared preference.
struct CuisineChips: View {
    @Binding var selection: Set<CuisineFilter>
    /// Optional dietary row (vegetarian / vegan / gluten-free), shown under the cuisines.
    var diet: Binding<DietFilter>? = nil
    var showsFastFoodToggle = true
    @State private var bumpedLimit = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if showsFastFoodToggle { NoFastFoodChip() }
                    // Cuisine chips tick when the selection changes (below), not per tap,
                    // so a tap past the limit plays only the warning.
                    Chip(label: "All", isSelected: selection.isEmpty, haptic: nil) { selection = [] }
                    ForEach(CuisineFilter.specific) { cuisine in
                        Chip(label: cuisine.label, isSelected: selection.contains(cuisine), haptic: nil) {
                            toggle(cuisine)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)

            if let diet {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DietFilter.specific) { option in
                            Chip(label: option.label, isSelected: diet.wrappedValue == option) {
                                diet.wrappedValue = diet.wrappedValue == option ? .none : option
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
                .accessibilityLabel("Dietary filter")
            }

            if selection.count > 1 {
                Text("Mixing \(CuisineFilter.summary(of: selection)) · up to \(CuisineFilter.maxSelection)")
                    .font(Theme.body(12, .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .sensoryFeedback(Haptic.tick, trigger: selection)
        .sensoryFeedback(.warning, trigger: bumpedLimit)
    }

    private func toggle(_ cuisine: CuisineFilter) {
        if selection.contains(cuisine) {
            selection.remove(cuisine)
        } else if selection.count < CuisineFilter.maxSelection {
            selection.insert(cuisine)
        } else {
            bumpedLimit += 1
        }
    }
}
