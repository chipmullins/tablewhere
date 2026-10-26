import SwiftUI
import MapKit
import PickerCore

/// Small map showing you, your search radius, and the results.
struct NearbyMap: View {
    @Environment(AppModel.self) private var model
    let places: [Place]

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
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
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 6) {
                Circle().fill(Theme.open).frame(width: 7, height: 7)
                Text("\(places.count) places within \(model.radiusLabel)")
            }
            .font(Theme.body(12, .semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.night.opacity(0.85), in: Capsule())
            .padding(12)
        }
        .onAppear { fitToRadius() }
        .onChange(of: model.radiusMiles) { fitToRadius() }
        .onChange(of: model.center.latitude) { fitToRadius() }
        .onChange(of: model.center.longitude) { fitToRadius() }
        .accessibilityLabel("Map of \(places.count) restaurants within \(model.radiusLabel)")
    }

    /// Zoom so the whole radius circle fits.
    private func fitToRadius() {
        let span = model.radiusMeters * 2.4
        withAnimation(.easeInOut(duration: 0.35)) {
            camera = .region(MKCoordinateRegion(center: model.center,
                                                latitudinalMeters: span,
                                                longitudinalMeters: span))
        }
    }
}
