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

    @State private var cuisines: Set<CuisineFilter> = []
    @State private var diet: DietFilter = .none
    @State private var results: [Place] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pick: Place?
    /// The same full-screen reveal as Spin, then the place's details.
    @State private var reveal: SpinRevealRequest?
    @State private var landed: Place?

    private let radiusMeters = 5 * Place.metersPerMile
    private let search: PlaceSearching = MapKitPlaceSearch()

    private var rules: Randomizer.Rules {
        model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories)
    }
    private var saved: [Place] { trip.sortedPlaces.map { $0.asPlace(from: trip.coordinate) } }
    private var visibleResults: [Place] { Randomizer.eligible(results, rules: rules) }

    var body: some View {
        let browse = visibleResults.filter { !trip.contains($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Trip")
                    Text(trip.cityName)
                        .font(Theme.display(32))
                        .foregroundStyle(Theme.text)
                    Text("\(saved.count) spots saved")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.muted)
                }

                Map(initialPosition: .region(MKCoordinateRegion(center: trip.coordinate,
                                                                latitudinalMeters: radiusMeters * 2.2,
                                                                longitudinalMeters: radiusMeters * 2.2))) {
                    ForEach(saved) { place in
                        Marker(place.name, systemImage: "suitcase.fill", coordinate: place.coordinate)
                            .tint(Theme.trip)
                    }
                    // Nearest 40 only: 100+ pins on a small map is one orange blob.
                    ForEach(Array(visibleResults.filter { !trip.contains($0) }.prefix(40))) { place in
                        Marker(place.name, systemImage: "fork.knife", coordinate: place.coordinate)
                            .tint(Theme.saffron)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                if !saved.isEmpty {
                    Button {
                        guard let choice = Randomizer.pick(from: saved, rules: rules) else { return }
                        pick = choice
                        reveal = SpinRevealRequest(names: Array(saved.shuffled().prefix(16)).map(\.name),
                                                   winner: choice.name)
                    } label: {
                        Label("Pick one of my saved spots", systemImage: "sparkles")
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

                CuisineChips(selection: $cuisines, diet: $diet)

                HStack {
                    Text("Worth the trip").font(Theme.display(22)).foregroundStyle(Theme.text)
                    Spacer()
                    // Refreshing results already on screen: a small spinner.
                    if isLoading && !browse.isEmpty { ProgressView().tint(Theme.muted) }
                }
                if let errorMessage {
                    Text(errorMessage).font(Theme.body(14)).foregroundStyle(Theme.danger)
                }
                if isLoading && browse.isEmpty {
                    // Same spacing as the result rows below.
                    VStack(spacing: 18) {
                        ForEach(0..<3, id: \.self) { _ in PlaceRowPlaceholder(tileSize: 50) }
                    }
                    .loadingSkeleton()
                }
                ForEach(browse) { place in
                    tripRow(place, isOnTrip: false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.night)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
        .task(id: "\(cuisines.map(\.rawValue).sorted())|\(diet.rawValue)") { await load() }
        .overlay {
            if let reveal {
                SpinReveal(names: reveal.names, winner: reveal.winner) {
                    self.reveal = nil
                    landed = pick  // then open it, with Directions and Call
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: reveal?.id)
        .navigationDestination(item: $landed) { PlaceDetailView(place: $0) }
    }

    private func tripRow(_ place: Place, isOnTrip: Bool) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: place) {
                HStack(spacing: 12) {
                    MonogramTile(name: place.name, category: place.category, size: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name)
                            .font(Theme.body(15, .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(place.category)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button { toggle(place) } label: {
                Text(isOnTrip ? "On trip" : "+ Trip")
                    .font(Theme.body(13, .bold))
                    .foregroundStyle(isOnTrip ? Theme.trip : Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(isOnTrip ? Theme.tripSoft : .clear, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isOnTrip ? Theme.trip : Theme.muted.opacity(0.4)))
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
        // After the first load, let quick chip taps settle (MapKit limits searches per minute).
        if !results.isEmpty {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let found = try await search.search(near: trip.coordinate, radiusMeters: radiusMeters, cuisines: cuisines, diet: diet)
            // A newer cuisine selection may have replaced this search.
            guard !Task.isCancelled else { return }
            results = found
        } catch is CancellationError {
        } catch {
            errorMessage = "Couldn’t load restaurants. Check your connection and try again."
        }
    }
}
