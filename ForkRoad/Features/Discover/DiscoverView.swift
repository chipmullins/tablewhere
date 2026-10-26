import SwiftUI
import SwiftData
import MapKit
import PickerCore

/// Home screen: map, search radius, cuisine chips, and nearby restaurants.
struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]
    @State private var showLocationPicker = false
    @State private var showSettings = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { searchText.trimmingCharacters(in: .whitespaces).count >= 2 }

    /// Results minus anything the user has blocked.
    private var visiblePlaces: [Place] {
        let rules = model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories)
        return Randomizer.eligible(model.places, rules: rules)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Text("Which way\nto dinner?")
                    .font(Theme.display(36))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                RestaurantSearchField(text: $searchText, isFocused: $searchFocused)
                if isSearching {
                    RestaurantSearchResults(query: searchText)
                } else {
                    NearbyMap(places: visiblePlaces)
                    RadiusControl()
                    cuisineChips
                    spinBanner
                    results
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.night)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
        .refreshable { await model.search() }
        .scrollDismissesKeyboard(.immediately)
    }

    private var header: some View {
        HStack {
            Button { showLocationPicker = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: model.isUsingCurrentLocation ? "Near you" : "Searching near")
                    HStack(spacing: 6) {
                        Image(systemName: model.isUsingCurrentLocation ? "location.fill" : "mappin")
                            .foregroundStyle(Theme.accentText)
                        Text(model.locationName)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(Theme.body(12, .bold))
                            .foregroundStyle(Theme.muted)
                    }
                    .font(Theme.body(16, .semibold))
                    .foregroundStyle(Theme.text)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Searching near \(model.locationName). Change location")
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
        .sheet(isPresented: $showLocationPicker) { LocationPickerView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var cuisineChips: some View {
        CuisineChips(selection: Binding(get: { model.cuisines }, set: { model.cuisines = $0 }),
                     diet: Binding(get: { model.diet }, set: { model.diet = $0 }))
    }

    private var spinBanner: some View {
        Button {
            model.spinSource = .nearby
            model.selectedTab = .spin
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "dice")
                    .font(Theme.body(22, .semibold))
                    .foregroundStyle(Theme.saffron)
                    .frame(width: 48, height: 48)
                    .background(Theme.onSaffron, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spin for it").font(Theme.display(19))
                    Text(model.cuisines.isEmpty
                         ? "Spin from \(visiblePlaces.count) places within \(model.radiusLabel)"
                         : "Spin from \(visiblePlaces.count) \(model.cuisineSummary) places")
                        .font(Theme.body(13, .medium))
                }
                Spacer()
                Image(systemName: "chevron.right").font(Theme.body(16, .bold))
            }
            .foregroundStyle(Theme.onSaffron)
            .padding(16)
            .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(visiblePlaces.isEmpty)
    }

    @ViewBuilder
    private var results: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Nearby").font(Theme.display(22)).foregroundStyle(Theme.text)
            Spacer()
            if model.isLoading { ProgressView().tint(Theme.muted) }
        }

        if model.location.isDenied && model.isUsingCurrentLocation {
            StateCard(icon: "location.slash",
                      title: "Location is off",
                      message: "Pick a city to search, or turn on location for ForkRoad in iPhone Settings.",
                      action: ("Pick a city", { showLocationPicker = true }))
        } else if model.errorMessage != nil && visiblePlaces.isEmpty {
            StateCard(icon: "wifi.slash",
                      title: "Can’t reach Apple Maps",
                      message: "Check your connection and try again.",
                      action: ("Try again", { Task { await model.search() } }))
        } else if !model.hasSearched || (model.isLoading && visiblePlaces.isEmpty) {
            ForEach(0..<4, id: \.self) { _ in PlaceRowPlaceholder() }
        } else if visiblePlaces.isEmpty {
            StateCard(icon: "fork.knife",
                      title: "Nothing nearby yet",
                      message: "No matches within \(model.radiusLabel). Try a bigger radius or fewer filters.",
                      action: model.radiusMiles < 10 ? ("Search 10 mi", { model.radiusMiles = 10 }) : nil)
        }

        LazyVStack(spacing: 10) {
            ForEach(visiblePlaces) { place in
                NavigationLink(value: place) { PlaceRow(place: place) }
                    .buttonStyle(.plain)
            }
        }
    }
}

/// Toggle that hides known fast-food chains everywhere in the app.
struct NoFastFoodChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.excludeFastFood.toggle()
        } label: {
            Label("No fast food", systemImage: model.excludeFastFood ? "checkmark" : "takeoutbag.and.cup.and.straw")
                .font(Theme.body(14, .semibold))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .foregroundStyle(model.excludeFastFood ? Theme.onSaffron : Theme.text)
                .background(model.excludeFastFood ? Theme.saffron : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(model.excludeFastFood ? .clear : Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.excludeFastFood ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: model.excludeFastFood)
    }
}
