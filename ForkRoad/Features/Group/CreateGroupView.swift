import SwiftUI
import SwiftData
import PickerCore

/// Sheet for starting a group pick: name it, choose vote or spin, pick places.
struct CreateGroupView: View {
    var onCreated: (GroupSession) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]

    @State private var title = "Dinner tonight"
    @State private var mode: GroupMode = .vote
    @State private var closesIn: Int? = 15
    @State private var selected: [Place] = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var query = ""

    static let maxVoteOptions = 8
    /// In a spin everyone adds one place, starting with you.
    private var maxOptions: Int { mode == .spin ? 1 : Self.maxVoteOptions }

    private var rules: Randomizer.Rules {
        model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories)
    }
    private func savedPlaces(in list: SavedList) -> [Place] {
        saved.filter { $0.list == list }.map { $0.asPlace(from: model.center) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $title)
                    Picker("How to decide", selection: $mode) {
                        Text("Vote").tag(GroupMode.vote)
                        Text("Spin").tag(GroupMode.spin)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) {
                        if mode == .spin && selected.count > 1 { selected = Array(selected.prefix(1)) }
                    }
                    if mode == .vote {
                        Picker("Voting closes", selection: $closesIn) {
                            Text("5 min").tag(Int?.some(5))
                            Text("15 min").tag(Int?.some(15))
                            Text("30 min").tag(Int?.some(30))
                            Text("When I lock it in").tag(Int?.none)
                        }
                    }
                } footer: {
                    Text(mode == .vote
                         ? "Most votes wins. Ties are broken fairly by the app. You can add up to 12 places; everyone else can suggest one."
                         : "Everyone adds one place, starting with you. Then you spin and the app picks one at random.")
                }
                .listRowBackground(Theme.surface)

                if !selected.isEmpty {
                    Section("Picked (\(selected.count))") {
                        ForEach(selected) { place in
                            Button { toggle(place) } label: {
                                HStack(spacing: 12) {
                                    MonogramTile(name: place.name, category: place.category, size: 30)
                                    Text(place.name).foregroundStyle(Theme.text).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Theme.muted)
                                        .accessibilityLabel("Remove")
                                }
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }

                GroupPlacePicker(
                    query: query,
                    center: model.center,
                    favorites: savedPlaces(in: .favorites),
                    interested: savedPlaces(in: .interested),
                    startingFilters: PlacePickerFilters(model.searchArea),
                    startingNearby: model.places,
                    rules: rules,
                    search: model.placeSearch,
                    accessory: { .check(isOn: selected.contains($0)) },
                    isDisabled: { mode == .vote && !selected.contains($0) && selected.count >= maxOptions },
                    onTap: toggle
                )

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                        .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search restaurants or cravings")
            .navigationTitle("New group pick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Start") { create() }
                            .bold()
                            .disabled(!canCreate)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(mode == .spin
                     ? (selected.isEmpty ? "Pick your one place for the wheel" : "Your pick: \(selected[0].name)")
                     : "\(selected.count) of up to \(maxOptions) selected")
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.night)
            }
        }
        .presentationBackground(Theme.night)
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (mode == .spin ? selected.count >= 1 : selected.count >= 2)
    }

    private func toggle(_ place: Place) {
        if let index = selected.firstIndex(of: place) {
            selected.remove(at: index)
        } else if mode == .spin {
            selected = [place]  // one pick: tapping another swaps it
        } else if selected.count < maxOptions {
            selected.append(place)
        }
    }

    private func create() {
        guard let name = Identity.displayName else { return }
        isCreating = true
        errorMessage = nil
        Task {
            defer { isCreating = false }
            do {
                let session = try await GroupService.shared.createSession(
                    title: title.trimmingCharacters(in: .whitespaces),
                    mode: mode,
                    options: selected.map { GroupOption(place: $0, addedBy: name) },
                    closesInMinutes: mode == .vote ? closesIn : nil,
                    displayName: name
                )
                onCreated(session)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
