import SwiftUI
import SwiftData
import PickerCore

/// The + on Lists: search Apple Maps for a restaurant and tap to save it,
/// or add one yourself if it isn't there (what you typed comes along).
struct AddToListSheet: View {
    var startingList: SavedList = .interested

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var saved: [SavedPlace]

    @State private var list: SavedList = .interested
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var searchedQuery: String?
    @State private var errorMessage: String?
    @State private var showManual = false
    @State private var justAdded: String?

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var actions: ListActions { ListActions(context: context) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Add to", selection: $list) {
                        Text("Want to try").tag(SavedList.interested)
                        Text("Favorites").tag(SavedList.favorites)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if trimmed.count < 2 {
                    Section {
                        Text("Search for a restaurant by name, or a craving like “tacos.” Results are around \(model.locationName).")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.muted)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    if isSearching && results.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.muted)
                            Text("Searching…").foregroundStyle(Theme.muted)
                        }
                        .listRowBackground(Color.clear)
                    } else if let errorMessage {
                        Text(errorMessage).foregroundStyle(Theme.danger).listRowBackground(Color.clear)
                    } else if searchedQuery == trimmed && results.isEmpty {
                        Text("No restaurants found for “\(trimmed)”.")
                            .foregroundStyle(Theme.muted)
                            .listRowBackground(Color.clear)
                    }
                    if !results.isEmpty {
                        Section("Results") {
                            ForEach(results) { place in
                                Button { add(place) } label: { row(place) }
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                }

                Section {
                    Button { showManual = true } label: {
                        Label(trimmed.isEmpty ? "Add a restaurant yourself" : "Can’t find it? Add “\(trimmed)” yourself",
                              systemImage: "square.and.pencil")
                            .font(Theme.body(15, .semibold))
                            .foregroundStyle(Theme.accentText)
                    }
                } footer: {
                    Text("For places Apple Maps doesn’t have, like a food truck or a new spot. Add the name, type, and an address if you know it.")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search restaurants or cravings")
            .autocorrectionDisabled()
            .task(id: trimmed) { await search() }
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.bold() } }
            .sheet(isPresented: $showManual) {
                CustomPlaceForm(startingList: list, startingName: trimmed) { dismiss() }
            }
            .sensoryFeedback(.success, trigger: justAdded)
        }
        .presentationBackground(Theme.night)
        .onAppear { list = startingList }
    }

    private func row(_ place: Place) -> some View {
        let current = saved.first { $0.placeID == place.id }?.list
        return HStack(spacing: 12) {
            MonogramTile(name: place.name, category: place.category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(Theme.text)
                Text([place.category, place.distanceLabel, place.address].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            if current == list {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.accentText)
                    .accessibilityLabel("Already on \(list.title)")
            } else if let current {
                Text("Move here")
                    .font(Theme.body(12, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .accessibilityLabel("On \(current.title). Move to \(list.title)")
            } else {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentText)
            }
        }
    }

    /// Saves it to the chosen list (or moves it there from the other list).
    private func add(_ place: Place) {
        guard actions.list(for: place) != list else { return }
        actions.toggle(place, in: list)
        justAdded = place.id
    }

    private func search() async {
        let text = trimmed
        guard text.count >= 2 else { results = []; searchedQuery = nil; errorMessage = nil; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            let found = try await model.searchRestaurants(text)
            guard !Task.isCancelled else { return }
            results = found
            searchedQuery = text
        } catch is CancellationError {
        } catch {
            errorMessage = "Couldn’t search right now. You can still add it yourself below."
            searchedQuery = text
        }
    }
}
