import SwiftUI
import MapKit

/// A spot a group place picker searches around instead of its usual center.
/// Only that picker uses it: Discover and Spin keep their own location.
struct PickerArea: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double

    init(name: String, coordinate: CLLocationCoordinate2D) {
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    /// "Chevy Chase", "Near S Limestone", or the city, for a spot on the map.
    static func spotName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        if let area = mark.subLocality { return area }
        if let street = mark.thoroughfare { return "Near \(street)" }
        return mark.locality
    }
}

/// Where a group picker looks: back to the usual area, a spot on the map, or
/// any city, neighborhood, address, or landmark. Shared by the app and the
/// iMessage extension (so no AppModel here).
struct PickerAreaSheet: View {
    /// The picker's usual center and its name ("Near you", "Lexington, KY").
    let defaultCenter: CLLocationCoordinate2D?
    let defaultName: String
    let current: PickerArea?
    /// Nil means "back to the usual area".
    let onPick: (PickerArea?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = CitySearch(citiesOnly: false)
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var showMap = false
    /// The spot tapped on the map; applied once the map has closed.
    @State private var mapPick: PickerArea?

    var body: some View {
        NavigationStack {
            List {
                // A plain field: the iMessage drawer doesn't do `.searchable` well.
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                        TextField("City, neighborhood, or address", text: $search.query)
                            .foregroundStyle(Theme.text)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                        if !search.query.isEmpty {
                            Button { search.query = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger)
                        .listRowBackground(Color.clear)
                }

                if search.query.isEmpty {
                    Section {
                        if defaultCenter != nil {
                            Button { finish(nil) } label: {
                                PickerAreaRow(icon: "location.fill", title: defaultName,
                                              subtitle: "Where ForkRoad is searching", selected: current == nil)
                            }
                        }
                        Button { showMap = true } label: {
                            PickerAreaRow(icon: "map.fill", title: "Choose on map",
                                          subtitle: "Tap anywhere, like the other side of town",
                                          selected: false)
                        }
                        if let current {
                            PickerAreaRow(icon: "mappin", title: current.name, subtitle: "Picked for this plan",
                                          selected: true)
                        }
                    }
                    .listRowBackground(Theme.surface)
                } else {
                    Section {
                        ForEach(search.results, id: \.self) { result in
                            Button { resolve(result) } label: {
                                PickerAreaRow(icon: "mappin.circle.fill", title: result.title,
                                              subtitle: result.subtitle, selected: false)
                            }
                            .disabled(isResolving)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .overlay { if isResolving { ProgressView().tint(Theme.muted) } }
            .navigationTitle("Search near")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            // Back from the map with a spot: use it and close this sheet too.
            .fullScreenCover(isPresented: $showMap, onDismiss: {
                if let mapPick { finish(mapPick) }
            }) {
                PickerMapView(start: current?.coordinate ?? defaultCenter) { mapPick = $0 }
            }
        }
        .presentationBackground(Theme.night)
    }

    private func finish(_ area: PickerArea?) {
        onPick(area)
        dismiss()
    }

    private func resolve(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        errorMessage = nil
        Task {
            defer { isResolving = false }
            do {
                let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
                guard let coordinate = response.mapItems.first?.placemark.location?.coordinate else {
                    errorMessage = "Couldn’t find that place."
                    return
                }
                finish(PickerArea(name: completion.title, coordinate: coordinate))
            } catch {
                errorMessage = "Couldn’t find that place. Check your connection and try again."
            }
        }
    }
}

private struct PickerAreaRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Theme.body(17, .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(16, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(Theme.body(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").font(Theme.body(15, .bold)).foregroundStyle(Theme.accentText)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Full-screen map: tap a spot, then "Search here".
struct PickerMapView: View {
    let start: CLLocationCoordinate2D?
    let onPick: (PickerArea) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var pin: CLLocationCoordinate2D?
    @State private var isNaming = false

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera) {
                    if let pin {
                        Marker("Search here", systemImage: "mappin", coordinate: pin)
                            .tint(Theme.saffron)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .onTapGesture { point in
                    guard let spot = proxy.convert(point, from: .local) else { return }
                    withAnimation(.snappy) { pin = spot }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top) {
                Label("Tap the spot to search around", systemImage: "hand.tap")
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.night)
            }
            .overlay(alignment: .bottom) {
                if pin != nil {
                    Button(action: confirm) {
                        HStack(spacing: 8) {
                            if isNaming { ProgressView().tint(Theme.onSaffron) }
                            Text("Search here")
                        }
                        .font(Theme.body(16, .bold))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isNaming)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)  // clear of the home indicator
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Choose on map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .toolbarBackground(Theme.night, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                if let start {
                    camera = .region(MKCoordinateRegion(center: start, latitudinalMeters: 8_000,
                                                        longitudinalMeters: 8_000))
                }
            }
        }
    }

    private func confirm() {
        guard let pin else { return }
        isNaming = true
        Task {
            // Name it after the neighborhood or street (a short wait at most).
            let name = await PickerArea.spotName(for: pin) ?? "Pinned spot"
            isNaming = false
            onPick(PickerArea(name: name, coordinate: pin))
            dismiss()
        }
    }
}
