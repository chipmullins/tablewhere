import SwiftUI
import SwiftData
import MapKit

/// Sheet for starting a trip: search for a city and name the trip.
struct NewTripView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var search = CitySearch()
    @State private var errorMessage: String?
    @State private var isResolving = false

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger)
                }
                ForEach(search.results, id: \.self) { result in
                    Button { choose(result) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).foregroundStyle(Theme.text)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle).font(Theme.body(13)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .disabled(isResolving)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "City, like Nashville")
            .overlay {
                if search.query.isEmpty {
                    ContentUnavailableView("Where are you headed?", systemImage: "airplane",
                                           description: Text("Search for a city to start a trip."))
                }
            }
            .navigationTitle("Plan a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationBackground(Theme.night)
    }

    private func choose(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        Task {
            defer { isResolving = false }
            do {
                let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
                guard let item = response.mapItems.first, let coordinate = item.placemark.location?.coordinate else {
                    errorMessage = "Couldn’t find that city."
                    return
                }
                let city = completion.title
                context.insert(Trip(name: "\(city) trip", cityName: city, coordinate: coordinate))
                dismiss()
            } catch {
                errorMessage = "Couldn’t find that city. Check your connection and try again."
            }
        }
    }
}
