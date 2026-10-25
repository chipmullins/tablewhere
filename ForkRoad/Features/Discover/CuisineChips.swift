import SwiftUI
import PickerCore

/// Multi-select cuisine chips. "All" clears the selection; tapping a cuisine
/// toggles it. Used on Discover, Spin, and trips.
struct CuisineChips: View {
    @Binding var selection: Set<CuisineFilter>
    var showsFastFoodToggle = true
    @State private var bumpedLimit = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if showsFastFoodToggle { NoFastFoodChip() }
                    Chip(label: "All", isSelected: selection.isEmpty) { selection = [] }
                    ForEach(CuisineFilter.specific) { cuisine in
                        Chip(label: cuisine.label, isSelected: selection.contains(cuisine)) {
                            toggle(cuisine)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)

            if selection.count > 1 {
                Text("Mixing \(CuisineFilter.summary(of: selection)) · up to \(CuisineFilter.maxSelection)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
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
