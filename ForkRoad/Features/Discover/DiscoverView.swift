import SwiftUI
import SwiftData
import MapKit
import PickerCore

/// Home screen: map, search radius, cuisine chips, and nearby restaurants.
struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]

    /// Results minus anything the user has blocked.
    private var visiblePlaces: [Place] {
        let rules = model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories)
        return Randomizer.eligible(model.places, rules: rules)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Text("What are we\neating tonight?")
                    .font(Theme.display(36))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                NearbyMap(places: visiblePlaces)
                RadiusControl()
                cuisineChips
                spinBanner
                results
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.night)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
        .refreshable { await model.search() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "Near you")
                Label(model.location.displayName, systemImage: "mappin")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .labelStyle(TintedIconLabelStyle())
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var cuisineChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NoFastFoodChip()
                ForEach(CuisineFilter.allCases) { cuisine in
                    Chip(label: cuisine.label, isSelected: model.cuisine == cuisine) {
                        model.cuisine = cuisine
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    private var spinBanner: some View {
        Button {
            model.spinSource = .nearby
            model.selectedTab = .spin
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "dice")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.saffron)
                    .frame(width: 48, height: 48)
                    .background(Theme.onSaffron, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Can’t decide?").font(Theme.display(19))
                    Text("Spin from \(visiblePlaces.count) places within \(model.radiusLabel)")
                        .font(.system(size: 13, weight: .medium))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold))
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

        if let error = model.errorMessage {
            Text(error).font(.system(size: 14)).foregroundStyle(Theme.danger)
        } else if visiblePlaces.isEmpty && !model.isLoading {
            Text("Nothing found within \(model.radiusLabel). Try a bigger radius.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
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
                .font(.system(size: 14, weight: .semibold))
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

/// Saffron icon, regular text.
private struct TintedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Theme.saffron)
            configuration.title
        }
    }
}
