import SwiftUI
import SwiftData
import MapKit
import PickerCore

/// One trip: browse restaurants in that city and save spots to the trip.
struct TripDetailView: View {
    @Bindable var trip: Trip

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]

    @State private var cuisine: CuisineFilter = .all
    @State private var results: [Place] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pick: Place?

    private let radiusMeters = 5 * Place.metersPerMile
    private let search: PlaceSearching = MapKitPlaceSearch()

    private var rules: Randomizer.Rules {
        model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories)
    }
    private var saved: [Place] { trip.sortedPlaces.map { $0.asPlace(from: trip.coordinate) } }
    private var visibleResults: [Place] { Randomizer.eligible(results, rules: rules) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Trip")
                    Text(trip.cityName)
                        .font(Theme.display(32))
                        .foregroundStyle(Theme.text)
                    Text("\(saved.count) spots saved")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }

                Map(initialPosition: .region(MKCoordinateRegion(center: trip.coordinate,
                                                                latitudinalMeters: radiusMeters * 2.2,
                                                                longitudinalMeters: radiusMeters * 2.2))) {
                    ForEach(saved) { place in
                        Marker(place.name, systemImage: "suitcase.fill", coordinate: place.coordinate)
                            .tint(Color(hex: 0x8FB4FF))
                    }
                    ForEach(visibleResults.filter { !trip.contains($0) }) { place in
                        Marker(place.name, systemImage: "fork.knife", coordinate: place.coordinate)
                            .tint(Theme.saffron)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                if !saved.isEmpty {
                    Button { pick = Randomizer.pick(from: saved, rules: rules) } label: {
                        Label("Pick one of my saved spots", systemImage: "dice")
                            .font(Theme.display(16))
                            .foregroundStyle(Theme.onSaffron)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    SectionLabel(text: "Saved for this trip")
                    ForEach(saved) { place in
                        tripRow(place, isOnTrip: true)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        NoFastFoodChip()
                        ForEach(CuisineFilter.allCases) { item in
                            Chip(label: item.label, isSelected: cuisine == item) { cuisine = item }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)

                HStack {
                    Text("Worth the trip").font(Theme.display(22)).foregroundStyle(Theme.text)
                    Spacer()
                    if isLoading { ProgressView().tint(Theme.muted) }
                }
                if let errorMessage {
                    Text(errorMessage).font(.system(size: 14)).foregroundStyle(Theme.danger)
                }
                ForEach(visibleResults.filter { !trip.contains($0) }) { place in
                    tripRow(place, isOnTrip: false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.night)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
        .task(id: cuisine) { await load() }
        .alert("How about…", isPresented: Binding(get: { pick != nil }, set: { if !$0 { pick = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pick.map { "\($0.name) · \($0.category)" } ?? "")
        }
    }

    private func tripRow(_ place: Place, isOnTrip: Bool) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: place) {
                HStack(spacing: 12) {
                    MonogramTile(name: place.name, size: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(place.category)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button { toggle(place) } label: {
                Text(isOnTrip ? "On trip" : "+ Trip")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isOnTrip ? Color(hex: 0x8FB4FF) : Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(isOnTrip ? Color(hex: 0x1B2433) : .clear, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isOnTrip ? Color(hex: 0x8FB4FF) : Theme.muted.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOnTrip ? "Remove \(place.name) from trip" : "Add \(place.name) to trip")
        }
        .padding(12)
        .card()
    }

    private func toggle(_ place: Place) {
        if let existing = (trip.places ?? []).first(where: { $0.placeID == place.id }) {
            context.delete(existing)
        } else {
            let item = TripPlace(place: place)
            context.insert(item)
            item.trip = trip
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            results = try await search.search(near: trip.coordinate, radiusMeters: radiusMeters, cuisine: cuisine)
        } catch is CancellationError {
        } catch {
            errorMessage = "Couldn’t load restaurants. Check your connection and try again."
        }
    }
}
