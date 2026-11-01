import SwiftUI
import UIKit
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
    /// How many of the nearby places the list shows (Show more adds 40).
    @State private var shownCount = 40
    @FocusState private var searchFocused: Bool
    @Namespace private var zoom

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
                Text("Which way\nto eat?")
                    .font(Theme.display(36))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                RestaurantSearchField(text: $searchText, isFocused: $searchFocused)
                if isSearching {
                    RestaurantSearchResults(query: searchText, zoom: zoom)
                } else if !model.hasLocation {
                    whereToLook
                } else {
                    HintCard(.discoverMap)
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
        .navigationDestination(for: Place.self) { place in
            PlaceDetailView(place: place).zoomDestination(id: place.id, ns: zoom)
        }
        // The widget's pick.
        .navigationDestination(item: Binding(get: { model.pendingPlace }, set: { model.pendingPlace = $0 })) {
            PlaceDetailView(place: $0)
        }
        .refreshable { await model.refresh() }
        .onChange(of: model.places.first?.id) { shownCount = 40 }
        .scrollDismissesKeyboard(.immediately)
    }

    /// Before ForkRoad knows where you are: ask, instead of guessing a city.
    private var whereToLook: some View {
        VStack(spacing: 14) {
            Image(systemName: model.location.isDenied ? "location.slash" : "location.magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 60, height: 60)
                .background(Theme.accentSoft, in: Circle())
            Text("Where should we look?")
                .font(Theme.display(22))
                .foregroundStyle(Theme.text)
            Text(model.location.isDenied
                 ? "Location is off for ForkRoad. Pick a city or neighborhood, or turn location on in Settings."
                 : "Use your location, or pick a city or neighborhood to find restaurants there.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if model.location.isDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(Theme.body(15, .bold))
                .foregroundStyle(Theme.accentText)
            } else {
                Button { model.useCurrentLocation() } label: {
                    Label("Use my location", systemImage: "location.fill")
                        .font(Theme.display(17))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button { showLocationPicker = true } label: {
                Text("Pick a city or neighborhood")
                    .font(Theme.body(15, .bold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .card(radius: 24)
        .padding(.top, 4)
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
            if !model.isUsingCurrentLocation && !model.location.isDenied {
                Button { model.useCurrentLocation() } label: {
                    Label("Use my location", systemImage: "location.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 36, height: 36)
                        .background(Theme.accentSoft, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use my location")
            }
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

    /// "165 places · 2 mi · Mexican · No fast food": what the spin will use.
    private var spinBannerDetail: String {
        var parts = ["\(visiblePlaces.count) \(visiblePlaces.count == 1 ? "place" : "places")", model.radiusLabel]
        if !model.cuisines.isEmpty { parts.append(model.cuisineSummary) }
        if model.diet != .none { parts.append(model.diet.label) }
        if model.excludeFastFood { parts.append("No fast food") }
        return parts.joined(separator: " · ")
    }

    private var spinBanner: some View {
        Button {
            model.spinSource = .nearby
            model.pendingSpin = true
            model.selectedTab = .spin
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(Theme.body(22, .semibold))
                    .foregroundStyle(Theme.saffron)
                    .frame(width: 48, height: 48)
                    .background(Theme.onSaffron, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spin for it").font(Theme.display(19))
                    Text(spinBannerDetail)
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
                      action: ("Try again", { Task { await model.refresh() } }))
        } else if !model.hasSearched || (model.isLoading && visiblePlaces.isEmpty) {
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in PlaceRowPlaceholder() }
            }
            .loadingSkeleton()
        } else if visiblePlaces.isEmpty {
            emptyResults
        }

        // Searches can bring back 100+ places: show the nearest first, more on request.
        let shown = visiblePlaces.prefix(shownCount)
        LazyVStack(spacing: 10) {
            ForEach(shown) { place in
                NavigationLink(value: place) {
                    PlaceRow(place: place).zoomSource(id: place.id, ns: zoom)
                }
                .buttonStyle(.plain)
            }
        }
        if visiblePlaces.count > shown.count {
            Button {
                shownCount += 40
            } label: {
                Text("Show more · \(visiblePlaces.count - shown.count) left")
                    .font(Theme.body(15, .bold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

extension DiscoverView {
    /// Filters you've turned on, so the empty state can offer to clear them.
    private var hasFilters: Bool {
        !model.cuisines.isEmpty || model.diet != .none || model.excludeFastFood
    }

    /// Nothing to show: say why (blacklist, filters, radius) and offer the fix.
    var emptyResults: some View {
        // Count only the blacklist here (No fast food is a filter, covered below).
        let blacklistRules: Randomizer.Rules = {
            var rules = model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories)
            rules.excludeFastFood = false
            return rules
        }()
        let hiddenByBlacklist = model.places.count - Randomizer.eligible(model.places, rules: blacklistRules).count
        // "vegan Thai", "Mexican", or just places.
        var what: [String] = []
        if model.diet != .none { what.append(model.diet.label.lowercased()) }
        if !model.cuisines.isEmpty { what.append(model.cuisineSummary) }
        let bigger: Double? = [1.0, 2, 3, 5, 10].first { $0 >= model.radiusMiles * 1.5 } ?? (model.radiusMiles < 10 ? 10 : nil)
        var message = what.isEmpty
            ? "No restaurants within \(model.radiusLabel)."
            : "Nothing \(what.joined(separator: " ")) within \(model.radiusLabel)."
        if hiddenByBlacklist > 0 {
            message += " \(hiddenByBlacklist) \(hiddenByBlacklist == 1 ? "is" : "are") on your blacklist."
        }
        message += bigger != nil ? " Widen the road a little and there’s plenty." : " Try fewer filters."
        let appModelForClear: AppModel = model
        let clear: () -> Void = {
            let model = appModelForClear
            model.cuisines = []
            model.diet = .none
            model.excludeFastFood = false
        }
        var primary: (title: String, action: () -> Void)?
        var secondary: (title: String, action: () -> Void)?
        if let bigger {
            let appModel: AppModel = model
            primary = (title: "Search \(RadiusSlider.label(bigger)) instead", action: { appModel.radiusMiles = bigger })
            if hasFilters { secondary = (title: "Clear filters", action: clear) }
        } else if hasFilters {
            primary = (title: "Clear filters", action: clear)
        }
        return EmptyState(art: .crossroads, title: "A dead end, for now", message: message,
                          primary: primary, secondary: secondary)
        .padding(.vertical, 16)
    }
}

/// Toggle that hides known fast-food chains everywhere in the app.
struct NoFastFoodChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        FastFoodChip(isOn: $model.excludeFastFood)
    }
}
