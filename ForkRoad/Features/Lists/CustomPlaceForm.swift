import SwiftUI
import SwiftData
import CoreLocation
import PickerCore

/// Add (or edit) a restaurant that isn't on Apple Maps: a food truck, a new
/// spot, Grandma's. Name and type are required; the address is optional.
/// Without an address it sits in the middle of the area you pick, so it
/// filters and spins there, but has no directions and isn't offered to groups.
struct CustomPlaceForm: View {
    /// Nil to add a new place.
    var existing: SavedPlace?
    var startingList: SavedList = .interested
    /// Called after saving or deleting (e.g. so a detail screen can close).
    var onFinish: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query(sort: \SavedArea.addedAt) private var areas: [SavedArea]

    @State private var name = ""
    @State private var category = "Restaurant"
    @State private var address = ""
    @State private var areaKey = AreaChoice.here.key
    @State private var list: SavedList = .interested
    @State private var skipInSpins = false
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var loaded = false

    /// Types to choose from. The cuisine names match the filter chips, so
    /// your places show up when you filter by cuisine.
    static let types = [
        "Restaurant", "Mexican", "Japanese", "BBQ", "Italian", "Pizza", "Burgers", "Chinese",
        "Thai", "Indian", "Café", "Bakery", "Breakfast", "Dessert", "Seafood", "Steakhouse",
        "Sandwiches", "Chicken", "Vegetarian", "Bar", "Food truck"
    ]

    /// Where a place without an address goes.
    enum AreaChoice: Hashable {
        case here
        case metro(Metro)
        case area(SavedArea)

        var key: String {
            switch self {
            case .here: return "here"
            case .metro(let metro): return "metro|\(metro.name)"
            case .area(let area): return "area|\(area.name)"
            }
        }

        static func == (a: AreaChoice, b: AreaChoice) -> Bool { a.key == b.key }
        func hash(into hasher: inout Hasher) { hasher.combine(key) }
    }

    private var metros: [Metro] { saved.metros.filter { !$0.isPending } }

    private var areaChoices: [(key: String, label: String, center: CLLocationCoordinate2D)] {
        var choices = [(key: AreaChoice.here.key,
                        label: "Here · \(model.currentCity ?? model.locationName)",
                        center: model.center)]
        let metroNames = Set(metros.map(\.name))
        for metro in metros {
            choices.append((key: AreaChoice.metro(metro).key, label: metro.label,
                            center: CLLocationCoordinate2D(latitude: metro.latitude, longitude: metro.longitude)))
        }
        for area in areas where !metroNames.contains(area.name) {
            choices.append((key: AreaChoice.area(area).key, label: area.name, center: area.coordinate))
        }
        return choices
    }

    private var chosenCenter: CLLocationCoordinate2D {
        areaChoices.first { $0.key == areaKey }?.center ?? model.center
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedAddress: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $category) {
                        ForEach(Self.types, id: \.self) { Text($0).tag($0) }
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    TextField("Address (optional)", text: $address, axis: .vertical)
                        .textContentType(.fullStreetAddress)
                        .lineLimit(1...3)
                    if trimmedAddress.isEmpty {
                        Picker("Area", selection: $areaKey) {
                            ForEach(areaChoices, id: \.key) { Text($0.label).tag($0.key) }
                        }
                    }
                } header: {
                    Text("Where is it?")
                } footer: {
                    Text(trimmedAddress.isEmpty
                         ? "No address? It’ll show up in that area’s lists and spins. Add one to get directions and use it in group picks."
                         : "With an address you get directions, and you can add it to group picks.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Picker("List", selection: $list) {
                        Text("Want to try").tag(SavedList.interested)
                        Text("Favorites").tag(SavedList.favorites)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Leave out of spins", isOn: $skipInSpins)
                        .tint(Theme.saffron)
                    TextField("Note: get the brisket, cash only…", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                .listRowBackground(Theme.surface)

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                        .listRowBackground(Theme.surface)
                }

                if existing != nil {
                    Section {
                        Button("Delete this place", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .navigationTitle(existing == nil ? "Add a restaurant" : "Edit restaurant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .bold()
                            .disabled(trimmedName.isEmpty)
                    }
                }
            }
            .confirmationDialog("Delete \(trimmedName.isEmpty ? "this place" : trimmedName)?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("It’s removed from your lists on all your devices.")
            }
            .onAppear(perform: load)
        }
        .presentationBackground(Theme.night)
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        list = startingList
        // Start in the area the Lists tab is filtered to.
        switch model.listCity {
        case .metro(let name): areaKey = "metro|\(name)"
        case .area(let name): areaKey = "area|\(name)"
        default: areaKey = AreaChoice.here.key
        }
        guard let existing else { return }
        name = existing.name
        category = Self.types.contains(existing.category) ? existing.category : "Restaurant"
        address = existing.address
        list = existing.list
        skipInSpins = existing.skipInSpins
        note = existing.note
        if !existing.hasExactLocation {
            // Pick the area it was placed in, if it's still one of the choices.
            let spot = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
            if let match = areaChoices.first(where: {
                CLLocation(latitude: $0.center.latitude, longitude: $0.center.longitude).distance(from: spot) < 100
            }) { areaKey = match.key }
        }
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        let addressText = trimmedAddress
        let center = chosenCenter
        Task {
            defer { isSaving = false }
            var spot = center
            var exact = false
            if !addressText.isEmpty {
                // Address unchanged on an edit: keep the spot we already found.
                if let existing, existing.hasExactLocation, existing.address == addressText {
                    spot = CLLocationCoordinate2D(latitude: existing.latitude, longitude: existing.longitude)
                } else {
                    guard let found = await Self.geocode(addressText, near: center) else {
                        errorMessage = "Couldn’t find that address. Check it, or clear it to save without one."
                        return
                    }
                    spot = found
                }
                exact = true
            }

            let item: SavedPlace
            if let existing {
                item = existing
                let moved = abs(item.latitude - spot.latitude) > 0.0001 || abs(item.longitude - spot.longitude) > 0.0001
                item.name = trimmedName
                item.category = category
                item.address = addressText
                item.latitude = spot.latitude
                item.longitude = spot.longitude
                item.hasExactLocation = exact
                if item.list != list { item.list = list }
                if moved { item.city = "" }
            } else {
                item = SavedPlace(customName: trimmedName, category: category, list: list,
                                  latitude: spot.latitude, longitude: spot.longitude,
                                  address: addressText, hasExactLocation: exact)
                context.insert(item)
                UsageStats.record(.customPlaces)
            }
            item.skipInSpins = skipInSpins
            item.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            try? context.save()
            Task { await ListActions.fillInCity(item) }
            dismiss()
            onFinish()
        }
    }

    private func delete() {
        guard let existing else { return }
        context.delete(existing)
        try? context.save()
        dismiss()
        onFinish()
    }

    /// Finds an address, preferring matches near the chosen area.
    private static func geocode(_ address: String, near center: CLLocationCoordinate2D) async -> CLLocationCoordinate2D? {
        let region = CLCircularRegion(center: center, radius: 50_000, identifier: "near")
        let marks = try? await CLGeocoder().geocodeAddressString(address, in: region)
        return marks?.first?.location?.coordinate
    }
}
