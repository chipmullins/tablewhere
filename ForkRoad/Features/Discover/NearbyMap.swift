import SwiftUI
import SwiftData
import MapKit
import PickerCore

/// Map showing you, your search radius, and the results.
///
/// Move around to look somewhere else: on the full-screen map, tap a spot to
/// search there; on either map, drag and tap "Search this area". Apple Maps returns about two dozen
/// places per search, so this is how you see the other side of town.
/// The small version on Discover expands to full screen.
struct NearbyMap: View {
    @Environment(AppModel.self) private var model
    let places: [Place]
    /// The full-screen version (bigger, with a hint and a Done button).
    var isExpanded = false

    @State private var camera: MapCameraPosition = .automatic
    /// Where the map is looking after the user drags it.
    @State private var viewCenter: CLLocationCoordinate2D?
    @State private var showFullMap = false
    /// Full map: the marker you tapped, shown as a card.
    @State private var selected: Place?

    /// Pins to draw: the nearest 40 on the small map (100+ pins there is one
    /// orange blob), up to 150 on the full map. `places` is nearest first.
    private var markerPlaces: [Place] {
        Array(places.prefix(isExpanded ? 150 : 40))
    }

    /// Show "Search this area" once the map has moved well away from the search center.
    private var movedAway: Bool {
        guard let viewCenter else { return false }
        let a = CLLocation(latitude: viewCenter.latitude, longitude: viewCenter.longitude)
        let b = CLLocation(latitude: model.center.latitude, longitude: model.center.longitude)
        return a.distance(from: b) > max(model.radiusMeters * 0.35, 300)
    }

    var body: some View {
        MapReader { proxy in
            // The small map doesn't pan or zoom, so scrolling Discover never
            // gets caught on it; a tap opens the big one.
            Map(position: $camera, interactionModes: isExpanded ? .all : []) {
                if model.isUsingCurrentLocation {
                    UserAnnotation()
                } else {
                    Marker(model.locationName, systemImage: "mappin", coordinate: model.center)
                        .tint(Theme.text)
                }
                MapCircle(center: model.center, radius: model.radiusMeters)
                    .foregroundStyle(Theme.saffron.opacity(0.08))
                    .stroke(Theme.saffron.opacity(0.6), lineWidth: 1.5)
                ForEach(markerPlaces) { place in
                    Marker(place.name, systemImage: "fork.knife", coordinate: place.coordinate)
                        .tint(selected?.id == place.id ? Theme.text : Theme.saffron)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .onMapCameraChange(frequency: .onEnd) { context in
                viewCenter = context.region.center
            }
            .onTapGesture { point in
                // On Discover, a tap opens the big map (so a stray tap while
                // scrolling never moves your search). On the big map, a tap
                // searches that spot.
                guard isExpanded else { showFullMap = true; return }
                // On (or right next to) a marker: show that place. Elsewhere:
                // close the card if one is open, or search that spot.
                if let place = marker(near: point, proxy: proxy) {
                    withAnimation(.snappy) { selected = place }
                    return
                }
                if selected != nil {
                    withAnimation(.snappy) { selected = nil }
                    return
                }
                guard let spot = proxy.convert(point, from: .local) else { return }
                search(at: spot)
            }
        }
        .frame(height: isExpanded ? nil : 170)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 0 : 22, style: .continuous))
        .overlay(alignment: .bottomLeading) { if selected == nil { countBadge } }
        .overlay(alignment: .bottom) {
            if isExpanded, let selected {
                MapPlaceCard(place: selected) { self.selected = nil }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 40)  // clear of the home indicator (the map ignores the bottom safe area)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: places.map(\.id)) {
            // New search: the card's place may be gone.
            if let selected, !places.contains(where: { $0.id == selected.id }) { self.selected = nil }
        }
        .overlay(alignment: .top) {
            if movedAway {
                Button {
                    if let viewCenter { search(at: viewCenter) }
                } label: {
                    Label("Search this area", systemImage: "arrow.clockwise")
                        .font(Theme.body(13, .bold))
                        .foregroundStyle(Theme.onSaffron)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Theme.saffron, in: Capsule())
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.top, isExpanded ? 12 : 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isExpanded {
                Button { showFullMap = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(Theme.body(13, .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 34, height: 34)
                        .background(Theme.night.opacity(0.85), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel("Expand map")
            }
        }
        .animation(.snappy, value: movedAway)
        .onAppear { fitToRadius() }
        .onChange(of: model.radiusMiles) { fitToRadius() }
        .onChange(of: model.center.latitude) { fitToRadius() }
        .onChange(of: model.center.longitude) { fitToRadius() }
        .sensoryFeedback(.selection, trigger: model.center.latitude)
        .fullScreenCover(isPresented: $showFullMap) { FullMapView() }
        .onChange(of: showFullMap) { if showFullMap { Hint.discoverMap.dismiss() } }
        .accessibilityLabel(isExpanded
            ? "Map of \(places.count) restaurants. Tap a restaurant to see it, or anywhere else to search there."
            : "Map of \(places.count) restaurants within \(model.radiusLabel). Opens a bigger map.")
    }

    private var countBadge: some View {
        HStack(spacing: 6) {
            if model.isLoading {
                ProgressView().controlSize(.mini).tint(Theme.text)
            } else {
                Circle().fill(Theme.open).frame(width: 7, height: 7)
            }
            Text(model.isLoading ? "Searching…" : "\(places.count) places within \(model.radiusLabel)")
        }
        .font(Theme.body(12, .semibold))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.night.opacity(0.85), in: Capsule())
        .padding(12)
    }

    /// The closest marker to a tap, if the tap is on or right by it. A marker's
    /// balloon sits just above its coordinate.
    private func marker(near point: CGPoint, proxy: MapProxy) -> Place? {
        var best: (place: Place, distance: CGFloat)?
        for place in markerPlaces {
            guard let pin = proxy.convert(place.coordinate, to: .local) else { continue }
            let dx = point.x - pin.x
            let dy = point.y - (pin.y - 18)
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < 30, distance < (best?.distance ?? .infinity) { best = (place, distance) }
        }
        return best?.place
    }

    private func search(at spot: CLLocationCoordinate2D) {
        viewCenter = nil
        model.searchHere(spot)
    }

    /// Zoom so the whole radius circle fits.
    private func fitToRadius() {
        let span = model.radiusMeters * 2.4
        withAnimation(.easeInOut(duration: 0.35)) {
            camera = .region(MKCoordinateRegion(center: model.center,
                                                latitudinalMeters: span,
                                                longitudinalMeters: span))
        }
        viewCenter = nil
    }
}

/// The map, full screen: easier to move around and pick a spot.
struct FullMapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]

    private var visiblePlaces: [Place] {
        Randomizer.eligible(model.places, rules: model.rules(blockedPlaces: blockedPlaces,
                                                             blockedCategories: blockedCategories))
    }

    var body: some View {
        NavigationStack {
            NearbyMap(places: visiblePlaces, isExpanded: true)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .top) {
                    Label("Tap a place to see it, or tap anywhere else to search there", systemImage: "hand.tap")
                        .font(Theme.body(13, .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.night)
                }
                .navigationTitle(model.locationName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if !model.isUsingCurrentLocation {
                            Button("My location", systemImage: "location") { model.useCurrentLocation() }
                                .disabled(model.location.isDenied)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.bold() }
                }
                .toolbarBackground(Theme.night, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

/// Full map: the place you tapped, with Details and Directions.
private struct MapPlaceCard: View {
    let place: Place
    var onClose: () -> Void
    @Environment(\.modelContext) private var context
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MonogramTile(name: place.name, category: place.category, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(Theme.body(16, .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("\(place.category) · \(place.distanceLabel)")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 32)
                        .background(Theme.surfaceHigh, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            HStack(spacing: 8) {
                Button { showDetail = true } label: {
                    Text("Details")
                        .font(Theme.body(15, .bold))
                        .foregroundStyle(Theme.night)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.text, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    PlaceLinks.openDirections(place)
                    VisitFollowUp.record(place, in: context)
                } label: {
                    Label("Directions", systemImage: "location.north.line")
                        .font(Theme.body(15, .bold))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
        .navigationDestination(isPresented: $showDetail) { PlaceDetailView(place: place) }
    }
}
