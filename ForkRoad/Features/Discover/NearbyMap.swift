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

    /// Show "Search this area" once the map has moved well away from the search center.
    private var movedAway: Bool {
        guard let viewCenter else { return false }
        let a = CLLocation(latitude: viewCenter.latitude, longitude: viewCenter.longitude)
        let b = CLLocation(latitude: model.center.latitude, longitude: model.center.longitude)
        return a.distance(from: b) > max(model.radiusMeters * 0.35, 300)
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if model.isUsingCurrentLocation {
                    UserAnnotation()
                } else {
                    Marker(model.locationName, systemImage: "mappin", coordinate: model.center)
                        .tint(Theme.text)
                }
                MapCircle(center: model.center, radius: model.radiusMeters)
                    .foregroundStyle(Theme.saffron.opacity(0.08))
                    .stroke(Theme.saffron.opacity(0.6), lineWidth: 1.5)
                ForEach(places) { place in
                    Marker(place.name, systemImage: "fork.knife", coordinate: place.coordinate)
                        .tint(Theme.saffron)
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
                guard let spot = proxy.convert(point, from: .local) else { return }
                search(at: spot)
            }
        }
        .frame(height: isExpanded ? nil : 170)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 0 : 22, style: .continuous))
        .overlay(alignment: .bottomLeading) { countBadge }
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
        .accessibilityLabel(isExpanded
            ? "Map of \(places.count) restaurants. Tap a spot to search there."
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
private struct FullMapView: View {
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
                    Label("Tap a spot, or drag and tap Search this area", systemImage: "hand.tap")
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
