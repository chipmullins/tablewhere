import SwiftUI
import SwiftData
import PickerCore

/// The search field on Discover.
struct RestaurantSearchField: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)
            TextField("Search restaurants or cravings", text: $text)
                .font(Theme.body(15, .medium))
                .foregroundStyle(Theme.text)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .card(radius: 16)
        .accessibilityElement(children: .contain)
    }
}

/// Search results that replace the rest of Discover while you're searching.
struct RestaurantSearchResults: View {
    let query: String
    /// Discover's namespace, so a result zooms into its details (iOS 18+).
    var zoom: Namespace.ID? = nil

    @Environment(AppModel.self) private var model
    @Query private var blockedPlaces: [BlockedPlace]

    @State private var results: [Place] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// The query the current results belong to, so "no results" never flashes mid-typing.
    @State private var searchedQuery: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isLoading && results.isEmpty ? "Searching…" : "Results near \(model.locationName)")
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if isLoading { ProgressView().tint(Theme.muted) }
            }

            if let errorMessage {
                Text(errorMessage).font(Theme.body(14)).foregroundStyle(Theme.danger)
            } else if !isLoading && searchedQuery == query && results.isEmpty {
                Text("No restaurants found for “\(query)”. Try a different spelling or a broader word like “pizza.”")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.muted)
            }

            LazyVStack(spacing: 10) {
                ForEach(results) { place in
                    NavigationLink(value: place) {
                        PlaceRow(place: place)
                            .overlay(alignment: .topTrailing) {
                                if blockedIDs.contains(place.id) {
                                    Text("BLACKLISTED")
                                        .font(Theme.body(10, .bold))
                                        .tracking(0.6)
                                        .foregroundStyle(Theme.danger)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                                        .padding(10)
                                }
                            }
                            .zoomSource(id: place.id, ns: zoom)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        // Debounced: waits until you stop typing for a moment.
        .task(id: query) { await search() }
    }

    private var blockedIDs: Set<String> { Set(blockedPlaces.map(\.placeID)) }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { results = []; searchedQuery = nil; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let found = try await model.searchRestaurants(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            searchedQuery = query
        } catch is CancellationError {
        } catch {
            errorMessage = "Couldn’t search right now. Check your connection and try again."
            searchedQuery = query
        }
    }
}
