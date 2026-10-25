import SwiftUI
import SwiftData

/// Trips tab: one entry per city you're planning to eat your way through.
struct TripsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @State private var showNewTrip = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Trip mode")
                    Text("Eat your way\nthrough a new city")
                        .font(Theme.display(32))
                        .foregroundStyle(Theme.text)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                Button { showNewTrip = true } label: {
                    Label("Plan a trip", systemImage: "plus")
                        .font(Theme.display(17))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .listRowBackground(Theme.saffron)
            }

            if trips.isEmpty {
                Text("Pick a city to browse its restaurants and save spots for your trip.")
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            } else {
                Section("Your trips") {
                    ForEach(trips) { trip in
                        NavigationLink(value: trip) {
                            HStack(spacing: 12) {
                                Image(systemName: "suitcase.fill")
                                    .foregroundStyle(Color(hex: 0x8FB4FF))
                                    .frame(width: 44, height: 44)
                                    .background(Color(hex: 0x1B2433), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(trip.name).font(Theme.body(16, .semibold))
                                    Text("\((trip.places ?? []).count) spots saved")
                                        .font(Theme.body(13))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in offsets.map { trips[$0] }.forEach { context.delete($0) } }
                    .listRowBackground(Theme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.night)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
        .sheet(isPresented: $showNewTrip) { NewTripView() }
    }
}
