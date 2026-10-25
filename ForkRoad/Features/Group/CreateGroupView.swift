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

    static let maxOptions = 8

    private var rules: Randomizer.Rules {
        model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories)
    }
    private var interested: [Place] {
        Randomizer.eligible(saved.map { $0.asPlace(from: model.center) }, rules: rules)
    }
    private var nearby: [Place] {
        let savedIDs = Set(interested.map(\.id))
        return Randomizer.eligible(model.places, rules: rules).filter { !savedIDs.contains($0.id) }
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
                         ? "Most votes wins. Ties are broken fairly by the app."
                         : "Friends can add places, then the app picks one at random.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    NoFastFoodChip()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                placeSection("From your Interested list", places: interested)
                placeSection("Nearby within \(model.radiusLabel)", places: nearby)

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                        .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
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
                Text("\(selected.count) of up to \(Self.maxOptions) selected")
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

    @ViewBuilder
    private func placeSection(_ header: String, places: [Place]) -> some View {
        if !places.isEmpty {
            Section(header) {
                ForEach(places) { place in
                    let isOn = selected.contains(place)
                    Button {
                        toggle(place)
                    } label: {
                        HStack(spacing: 12) {
                            MonogramTile(name: place.name, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).foregroundStyle(Theme.text)
                                Text("\(place.category) · \(place.distanceLabel)")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(Theme.body(22))
                                .foregroundStyle(isOn ? Theme.saffron : Theme.muted.opacity(0.5))
                        }
                    }
                    .disabled(!isOn && selected.count >= Self.maxOptions)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .listRowBackground(Theme.surface)
        }
    }

    private func toggle(_ place: Place) {
        if let index = selected.firstIndex(of: place) {
            selected.remove(at: index)
        } else if selected.count < Self.maxOptions {
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
