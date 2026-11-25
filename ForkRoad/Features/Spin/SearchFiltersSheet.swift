import SwiftUI
import PickerCore

/// Where, how far, and what kind of food: the same settings everywhere
/// (Spin → Nearby and Discover share them; changing one changes both).
struct SearchFiltersSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showLocationPicker = false
    @State private var showMap = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button { showLocationPicker = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: model.isUsingCurrentLocation ? "location.fill" : "mappin")
                                .foregroundStyle(Theme.accentText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Searching near").font(Theme.body(12)).foregroundStyle(Theme.muted)
                                Text(model.locationName).font(Theme.body(16, .semibold)).foregroundStyle(Theme.text)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(Theme.body(12, .bold)).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 60)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Search for a city or neighborhood")

                    HStack(spacing: 8) {
                        if !model.isUsingCurrentLocation && !model.location.isDenied {
                            chip("Use my location", icon: "location.fill") { model.useCurrentLocation() }
                        }
                        chip("Choose on map", icon: "map.fill") { showMap = true }
                        Spacer(minLength: 0)
                    }

                    RadiusSlider(miles: $model.radiusMiles)
                    CuisineChips(selection: $model.cuisines, diet: $model.diet)
                }
                .padding(16)
            }
            .background(Theme.night)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("Show places") { dismiss() }
                    .buttonStyle(.sleekPrimary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.bold() } }
            .sheet(isPresented: $showLocationPicker) { LocationPickerView() }
            .fullScreenCover(isPresented: $showMap) { FullMapView() }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.night)
    }

    private func chip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(Theme.body(14, .semibold))
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Theme.accentSoft, in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}
