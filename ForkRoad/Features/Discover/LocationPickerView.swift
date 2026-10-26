import SwiftUI
import MapKit

/// Sheet for choosing where to search: current location, a recent place,
/// or any city, neighborhood, address, or landmark.
struct LocationPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var search = CitySearch(citiesOnly: false)
    @State private var recent = ChosenLocation.recent
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger)
                        .listRowBackground(Color.clear)
                }

                if search.query.isEmpty {
                    Section {
                        Button {
                            model.useCurrentLocation()
                            dismiss()
                        } label: {
                            row(icon: "location.fill",
                                title: "Current location",
                                subtitle: model.location.isDenied
                                    ? "Location is off for ForkRoad in Settings"
                                    : (model.location.placeName ?? "Use where you are now"),
                                selected: model.isUsingCurrentLocation)
                        }
                        .disabled(model.location.isDenied)
                    }
                    .listRowBackground(Theme.surface)

                    if !recent.isEmpty {
                        Section("Recent") {
                            ForEach(recent) { place in
                                Button { pick(place) } label: {
                                    row(icon: "clock.arrow.circlepath", title: place.name, subtitle: place.subtitle,
                                        selected: model.chosenLocation?.id == place.id)
                                }
                                .swipeActions {
                                    Button("Remove", role: .destructive) {
                                        ChosenLocation.forget(place)
                                        recent = ChosenLocation.recent
                                    }
                                }
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                } else {
                    Section {
                        ForEach(search.results, id: \.self) { result in
                            Button { resolve(result) } label: {
                                row(icon: "mappin.circle.fill", title: result.title, subtitle: result.subtitle, selected: false)
                            }
                            .disabled(isResolving)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .searchable(text: $search.query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "City, neighborhood, or address")
            .overlay {
                if isResolving { ProgressView().tint(Theme.muted) }
            }
            .navigationTitle("Search near")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationBackground(Theme.night)
    }

    private func row(icon: String, title: String, subtitle: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Theme.body(17, .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(16, .semibold)).foregroundStyle(Theme.text)
                if !subtitle.isEmpty {
                    Text(subtitle).font(Theme.body(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").font(Theme.body(15, .bold)).foregroundStyle(Theme.accentText)
            }
        }
        .contentShape(Rectangle())
    }

    private func pick(_ place: ChosenLocation) {
        model.choose(place)
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
                pick(ChosenLocation(name: completion.title, subtitle: completion.subtitle,
                                    latitude: coordinate.latitude, longitude: coordinate.longitude))
            } catch {
                errorMessage = "Couldn’t find that place. Check your connection and try again."
            }
        }
    }
}
