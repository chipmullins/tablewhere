import SwiftUI
import CoreLocation
import PickerCore

/// "Surprise us": where to look, the filters, and the places the wheel drew
/// (up to 12 at random from what's nearby). Shuffle draws again. Everyone in
/// the group sees this wheel; the creator spins it from the plan.
struct SurpriseWheelSection: View {
    let center: CLLocationCoordinate2D?
    let centerName: String
    let startingFilters: PlacePickerFilters
    /// Discover's results, reused when nothing's changed (saves a search).
    let startingNearby: [Place]
    let rules: Randomizer.Rules
    let search: PlaceSearching
    @Binding var area: PickerArea?
    @Binding var filters: PlacePickerFilters
    @Binding var wheel: [Place]
    @Binding var isLoading: Bool

    @State private var pool: [Place] = []
    @State private var loadError: String?
    @State private var showAreaSheet = false
    @State private var showAreaMap = false
    @State private var shuffles = 0
    /// Places you swiped off the wheel: never drawn again while setting up.
    @State private var removed: Set<String> = []

    private struct Key: Equatable {
        var filters: PlacePickerFilters
        var area: PickerArea?
    }

    private var searchCenter: CLLocationCoordinate2D? { area?.coordinate ?? center }

    var body: some View {
        Section {
            areaRow
                // On one row, not the Section (a List can repeat Section modifiers per row).
                .task(id: Key(filters: filters, area: area)) { await load() }
                .sheet(isPresented: $showAreaSheet) {
                    PickerAreaSheet(defaultCenter: center, defaultName: centerName, current: area) { area = $0 }
                }
                .fullScreenCover(isPresented: $showAreaMap) {
                    PickerMapView(start: searchCenter) { area = $0 }
                }
            RadiusSlider(miles: $filters.radiusMiles)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            CuisineChips(selection: $filters.cuisines, diet: $filters.diet)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
        } header: {
            Text("Where to look")
        }

        Section {
            if isLoading && wheel.isEmpty {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceHigh).frame(width: 28, height: 28)
                        RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceHigh).frame(width: 150, height: 12)
                    }
                    .accessibilityHidden(true)
                }
            } else if let loadError {
                Text(loadError).font(Theme.body(14)).foregroundStyle(Theme.muted)
            } else if wheel.isEmpty {
                Text(searchCenter == nil
                     ? "Choose where to look above."
                     : "Nothing nearby matches. Try a bigger radius or fewer filters.")
                    .font(Theme.body(14)).foregroundStyle(Theme.muted)
            } else {
                ForEach(wheel) { place in
                    HStack(spacing: 12) {
                        MonogramTile(name: place.name, category: place.category, size: 28)
                        Text(place.name).font(Theme.body(15, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(place.distanceLabel).font(Theme.body(12)).foregroundStyle(Theme.muted)
                    }
                    .accessibilityElement(children: .combine)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { withAnimation(.snappy) { remove(place) } } label: {
                            Label("Remove", systemImage: "xmark")
                        }
                    }
                    .accessibilityAction(named: "Remove from the wheel") { withAnimation(.snappy) { remove(place) } }
                }
            }
        } header: {
            HStack {
                Text(wheel.isEmpty ? "On the wheel" : "On the wheel (\(wheel.count))")
                Spacer()
                if available.count > wheel.count {
                    Button {
                        shuffles += 1
                        withAnimation(.snappy) { draw() }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(Theme.body(13, .bold))
                            .textCase(nil)
                    }
                    .foregroundStyle(Theme.accentText)
                    .sensoryFeedback(Haptic.tick, trigger: shuffles)
                }
            }
        } footer: {
            Text(available.count > wheel.count
                 ? "\(wheel.count) drawn at random from \(available.count) places. Swipe one away to swap it. Friends see this wheel, then you spin it."
                 : "Swipe one away to take it off. Friends see this wheel, then you spin it and it picks one at random.")
        }
        .listRowBackground(Theme.surface)
    }

    private var areaRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showAreaSheet = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: area == nil ? "location.fill" : "mappin")
                        .foregroundStyle(Theme.accentText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Near").font(Theme.body(12)).foregroundStyle(Theme.muted)
                        Text(area?.name ?? (center == nil ? "Choose a place" : centerName))
                            .font(Theme.body(16, .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(Theme.body(12, .bold)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Search for a city, neighborhood, or address")

            HStack(spacing: 8) {
                if area != nil && center != nil {
                    chip("Reset area", icon: "arrow.uturn.backward") { area = nil }
                }
                chip("Choose on map", icon: "map.fill") { showAreaMap = true }
                Spacer(minLength: 0)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
    }

    private func chip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(Theme.body(14, .semibold))
                .foregroundStyle(Theme.accentText)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Theme.accentSoft, in: Capsule())
        }
        .buttonStyle(.pressable)
    }

    /// What can be drawn: the nearby pool minus anything you swiped away.
    private var available: [Place] { pool.filter { !removed.contains($0.id) } }

    /// Up to 12 at random from everything that's allowed (blacklists, no fast
    /// food, the rest of your spin rules, and nothing you swiped away).
    private func draw() {
        wheel = Array(available.shuffled().prefix(GroupSession.maxOptions))
    }

    /// Takes one off and, when there are more nearby, draws one in its place.
    private func remove(_ place: Place) {
        removed.insert(place.id)
        guard let index = wheel.firstIndex(of: place) else { return }
        let onWheel = Set(wheel.map(\.id))
        if let next = available.filter({ !onWheel.contains($0.id) }).randomElement() {
            wheel[index] = next
        } else {
            wheel.remove(at: index)
        }
    }

    private func load() async {
        loadError = nil
        // Never leave the old area's places up (Start would send them).
        wheel = []
        pool = []
        // Same place and filters as Discover: use what it already found.
        if area == nil && filters == startingFilters && !startingNearby.isEmpty {
            pool = Randomizer.eligible(startingNearby, rules: rules)
            draw()
            isLoading = false
            return
        }
        guard let searchCenter else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        // Wait until the slider or chips settle (MapKit limits searches per minute).
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        do {
            let found = try await search.search(near: searchCenter,
                                                radiusMeters: filters.radiusMiles * Place.metersPerMile,
                                                cuisines: filters.cuisines,
                                                diet: filters.diet)
            guard !Task.isCancelled else { return }
            pool = Randomizer.eligible(found, rules: rules)
            draw()
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            loadError = "Couldn’t load nearby places. Check your connection."
        }
    }
}
