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
    @Query private var saved: [SavedPlace]
    @State private var showLocationPicker = false
    @State private var showSettings = false
    @State private var showFilters = false
    @State private var showMap = false
    @State private var searchText = ""
    /// How many of the nearby places the list shows (Show more adds 40).
    @State private var shownCount = 40
    @FocusState private var searchFocused: Bool
    @Namespace private var zoom

    private var favoriteIDs: Set<String> {
        Set(saved.filter { $0.list == .favorites }.map(\.placeID))
    }

    private var isSearching: Bool { searchText.trimmingCharacters(in: .whitespaces).count >= 2 }

    /// Results minus anything the user has blocked.
    private var visiblePlaces: [Place] {
        let rules = model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories)
        return Randomizer.eligible(model.places, rules: rules)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                RestaurantSearchField(text: $searchText, isFocused: $searchFocused)
                if isSearching {
                    RestaurantSearchResults(query: searchText, zoom: zoom)
                } else if !model.hasLocation {
                    whereToLook
                } else {
                    cuisineChips
                    filterPills
                    HintCard(.discoverMap)
                    spinBanner
                    LateNightNote(placeCount: visiblePlaces.count)
                    results
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
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
        .sheet(isPresented: $showLocationPicker) { LocationPickerView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showFilters) { SearchFiltersSheet() }
        .fullScreenCover(isPresented: $showMap) { FullMapView() }
        .onChange(of: showMap) { if showMap { Hint.discoverMap.dismiss() } }
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
                 ? "Location is off for Tablewhere. Pick a city or neighborhood, or turn location on in Settings."
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
                .buttonStyle(.pressable)
            }
            Button { showLocationPicker = true } label: {
                Text("Pick a city or neighborhood")
                    .font(Theme.body(15, .bold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .card(radius: 24)
        .padding(.top, 4)
    }

    /// "Find a place" and Settings.
    private var header: some View {
        HStack(alignment: .center) {
            Text("Find a place")
                .font(Theme.display(34))
                .tracking(-1)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            RoundIconButton(label: "Settings", systemImage: "gearshape", size: 44) { showSettings = true }
        }
        .padding(.top, 12)
    }

    /// Where you're looking and how far, as two small pills.
    private var filterPills: some View {
        HStack(spacing: 8) {
            Button { showLocationPicker = true } label: {
                pill(icon: model.isUsingCurrentLocation ? "location.fill" : "mappin", text: model.locationName)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Searching near \(model.locationName). Change location")
            if !model.isUsingCurrentLocation && !model.location.isDenied {
                Button { model.useCurrentLocation() } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 36, height: 36)
                        .background(Theme.accentSoft, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Use my location")
            }
            Button { showFilters = true } label: {
                pill(icon: "slider.horizontal.3", text: filtersPillText)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Filters: \(filtersPillText)")
            .accessibilityHint("Change how far, diet, and what kind of food")
            Spacer(minLength: 0)
        }
    }

    private var filtersPillText: String {
        var parts = [model.radiusLabel]
        if model.diet != .none { parts.append(model.diet.label) }
        return parts.joined(separator: " · ")
    }

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accentText)
            Text(text)
                .font(Theme.body(14, .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }

    /// Cuisines up top (diet lives in Filters).
    private var cuisineChips: some View {
        CuisineChips(selection: Binding(get: { model.cuisines }, set: { model.cuisines = $0 }))
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
            model.eatIn = false
            model.pendingSpin = true
            model.selectedTab = .spin
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.onSaffron)
                    .frame(width: 44, height: 44)
                    .background(Theme.saffron, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spin for it").font(Theme.body(15, .bold)).foregroundStyle(Theme.text)
                    Text(spinBannerDetail)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.button + 2, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.pressable)
        .disabled(visiblePlaces.isEmpty)
    }

    @ViewBuilder
    private var results: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Nearby").font(Theme.display(18)).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            if model.isLoading { ProgressView().tint(Theme.muted).padding(.leading, 4) }
            Spacer()
            Button("Map") { showMap = true }
                .font(Theme.body(14, .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 44)
                .accessibilityLabel("Show on map")
                .accessibilityHint("Map of \(plural(visiblePlaces.count, "restaurant")) within \(model.radiusLabel)")
        }
        .padding(.top, 4)

        if model.location.isDenied && model.isUsingCurrentLocation {
            StateCard(icon: "location.slash",
                      title: "Location is off",
                      message: "Pick a city to search, or turn on location for Tablewhere in iPhone Settings.",
                      action: ("Pick a city", { showLocationPicker = true }))
        } else if model.errorMessage != nil && visiblePlaces.isEmpty {
            StateCard(icon: "wifi.slash",
                      title: "Can’t reach Apple Maps",
                      message: "Check your connection and try again.",
                      action: ("Try again", { Task { await model.refresh() } }))
        } else if !model.hasSearched || (model.isLoading && visiblePlaces.isEmpty) {
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in PlaceRowPlaceholder() }
            }
            .loadingSkeleton()
        } else if visiblePlaces.isEmpty {
            emptyResults
        }

        // Searches can bring back 100+ places: show the nearest first, more on request.
        let shown = visiblePlaces.prefix(shownCount)
        LazyVStack(spacing: 0) {
            ForEach(shown) { place in
                HStack(spacing: 4) {
                    NavigationLink(value: place) {
                        PlaceRow(place: place, showsChevron: false, showsDivider: false).zoomSource(id: place.id, ns: zoom)
                    }
                    .buttonStyle(.pressable)
                    FavoriteHeart(place: place, isFavorite: favoriteIDs.contains(place.id))
                }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
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
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            }
            .buttonStyle(.pressable)
            .padding(.top, 8)
        }
    }
}

/// The heart at the end of a Discover row: adds to (or takes off) Favorites.
private struct FavoriteHeart: View {
    let place: Place
    let isFavorite: Bool
    @Environment(\.modelContext) private var context

    var body: some View {
        let actions = ListActions(context: context)
        Button {
            actions.toggle(place, in: .favorites)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isFavorite ? Theme.accentText : Theme.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(Haptic.tick, trigger: isFavorite)
        .accessibilityLabel("Favorite \(place.name)")
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
        .accessibilityValue(isFavorite ? "On" : "Off")
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
            rules.excludeCoffeeAndSweets = false
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

/// The "Filters" chip: No fast food and No coffee & sweets (the latter on by
/// default; your saved lists keep their coffee shops).
struct PlaceFiltersChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        FoodFiltersChip(noFastFood: $model.excludeFastFood, noCoffeeSweets: $model.excludeCoffeeAndSweets)
    }
}
