import SwiftUI
import SwiftData
import PickerCore

/// Spin → Custom: the places on your hand-picked wheel, with Add and Clear.
struct PickedWheelEditor: View {
    @Binding var showPicker: Bool
    @Environment(AppModel.self) private var model
    @State private var removeTaps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.pickedWheel.isEmpty {
                Text("Build your own wheel: search any restaurant, grab some from your lists, or type anything, like “Leftovers.”")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.muted)
            } else {
                FlowChips(items: model.pickedWheel) { place in
                    removeTaps += 1
                    let before = model.pickedWheel
                    model.togglePicked(place)
                    UndoCenter.shared.show("Took \(place.name) off your wheel") { [model] in
                        model.pickedWheel = before
                    }
                }
            }
            HStack(spacing: 8) {
                Button { showPicker = true } label: {
                    Label(model.pickedWheel.isEmpty ? "Add places" : "Add more", systemImage: "plus.circle.fill")
                        .font(Theme.body(14, .bold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Theme.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.pickedWheel.count >= AppModel.maxPicked)
                if !model.pickedWheel.isEmpty {
                    Button("Clear") {
                        removeTaps += 1
                        let before = model.pickedWheel
                        model.pickedWheel = []
                        UndoCenter.shared.show("Cleared your wheel") { [model] in
                            model.pickedWheel = before
                        }
                    }
                        .font(Theme.body(14, .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Theme.surface, in: Capsule())
                        .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .sensoryFeedback(Haptic.destructive, trigger: removeTaps)
    }
}

/// Wrapping row of removable chips ("Sora Ramen ✕").
private struct FlowChips: View {
    let items: [Place]
    let onRemove: (Place) -> Void

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(items) { place in
                Button { onRemove(place) } label: {
                    HStack(spacing: 6) {
                        Text(place.name).lineLimit(1)
                        Image(systemName: "xmark")
                            .font(Theme.body(10, .bold))
                            .foregroundStyle(Theme.muted)
                    }
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(place.name) from the wheel")
            }
        }
    }
}

/// Lays children out left to right, wrapping to new lines.
private struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Add places to your wheel: search, your lists, nearby (with Discover's
/// filters), or type anything.
struct WheelPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]
    @State private var query = ""
    @State private var uncheckTaps = 0
    @State private var typedTaps = 0

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func savedPlaces(_ list: SavedList) -> [Place] {
        saved.filter { $0.list == list }.map { $0.asPlace(from: model.center) }
    }
    private var pickedIDs: Set<String> { Set(model.pickedWheel.map(\.id)) }

    var body: some View {
        NavigationStack {
            List {
                // What's on the wheel now (tap to take one off).
                if trimmed.isEmpty && !model.pickedWheel.isEmpty {
                    Section("On your wheel") {
                        ForEach(model.pickedWheel) { place in
                            Button {
                                uncheckTaps += 1
                                model.togglePicked(place)
                            } label: {
                                HStack(spacing: 12) {
                                    MonogramTile(name: place.name, category: place.category, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(place.name).foregroundStyle(Theme.text)
                                        Text(place.id.hasPrefix("typed|") ? "Typed in" : place.category)
                                            .font(Theme.body(12))
                                            .foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(Theme.body(22))
                                        .foregroundStyle(Theme.accentText)
                                        .accessibilityHidden(true)
                                }
                            }
                            .accessibilityLabel("\(place.name), on your wheel")
                            .accessibilityHint("Takes it off the wheel")
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
                GroupPlacePicker(
                    query: query,
                    center: model.center,
                    favorites: savedPlaces(.favorites),
                    interested: savedPlaces(.interested),
                    startingFilters: PlacePickerFilters(model.searchArea),
                    startingNearby: model.places,
                    rules: model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories),
                    search: model.placeSearch,
                    accessory: { .check(isOn: pickedIDs.contains($0.id)) },
                    isDisabled: { !pickedIDs.contains($0.id) && model.pickedWheel.count >= AppModel.maxPicked },
                    onTap: { model.togglePicked($0) }
                )
                // Below the results, for things that aren't restaurants.
                if !trimmed.isEmpty {
                    Section {
                        Button {
                            typedTaps += 1
                            model.addTypedPick(trimmed)
                            query = ""
                        } label: {
                            Label("Add “\(trimmed)” as typed", systemImage: "text.cursor")
                                .font(Theme.body(15, .semibold))
                                .foregroundStyle(Theme.accentText)
                        }
                        .disabled(model.pickedWheel.count >= AppModel.maxPicked)
                    } header: {
                        Text("Not a restaurant?")
                    } footer: {
                        Text("For anything else, like “Leftovers” or “Mom’s.”")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .sensoryFeedback(Haptic.tick, trigger: uncheckTaps)
            .sensoryFeedback(Haptic.commit, trigger: typedTaps)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search restaurants, or type anything")
            .navigationTitle("Your wheel · \(model.pickedWheel.count)")
            .navigationBarTitleDisplayMode(.inline)
            // Always reachable, even while the search field has the top bar.
            .safeAreaInset(edge: .bottom) {
                Button { dismiss() } label: {
                    Text(model.pickedWheel.isEmpty ? "Done" : "Done · \(model.pickedWheel.count) on your wheel")
                        .font(Theme.display(17))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.night)
            }
        }
        .presentationBackground(Theme.night)
    }
}
