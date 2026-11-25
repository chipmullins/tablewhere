import SwiftUI
import SwiftData
import MapKit
import PickerCore

/// Restaurant screen: Look Around street view, actions, menu, and address.
struct PlaceDetailView: View {
    let place: Place

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var lookAround: MKLookAroundScene?
    @State private var browserURL: URL?
    @State private var showBlockOptions = false
    @State private var refresh = 0  // re-render after save/block
    @State private var showEdit = false

    private var actions: ListActions { ListActions(context: context) }

    var body: some View {
        let onList = actions.list(for: place)
        let record = actions.saved(place)
        let isCustom = record?.isCustom ?? false
        let hasDirections = record?.hasExactLocation ?? true
        let _ = refresh

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if hasDirections {
                    hero
                } else {
                    // No address: there's no real spot to show.
                    ZStack {
                        Theme.surface
                        VStack(spacing: 8) {
                            MonogramTile(name: place.name, category: place.category, size: 72)
                            Text("No address yet. Tap Edit to add one for directions.")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.top, 60)
                    }
                    .frame(height: 300)
                }

                VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(place.name)
                        .font(Theme.display(34))
                        .tracking(-1)
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(isCustom
                         ? (hasDirections ? "\(place.category) · \(place.distanceLabel) · added by you"
                                          : "\(place.category) · added by you · no address")
                         : "\(place.category) · \(place.distanceLabel)")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.muted)
                }

                // Icon-only actions, then one primary: directions.
                HStack {
                    IconAction(label: "Call", systemImage: "phone") {
                        if let url = PlaceLinks.phoneURL(place) { openURL(url) }
                    }
                    .disabled(place.phoneNumber == nil)
                    Spacer(minLength: 6)
                    IconAction(label: "Favorite", systemImage: onList == .favorites ? "heart.fill" : "heart",
                               isOn: onList == .favorites) {
                        actions.toggle(place, in: .favorites)
                        refresh += 1
                    }
                    Spacer(minLength: 6)
                    IconAction(label: "Try later", systemImage: onList == .interested ? "bookmark.fill" : "bookmark",
                               isOn: onList == .interested, hint: "Saves it to your To try list") {
                        actions.toggle(place, in: .interested)
                        refresh += 1
                    }
                    Spacer(minLength: 6)
                    if isCustom {
                        IconAction(label: "Edit", systemImage: "pencil") { showEdit = true }
                    } else {
                        IconAction(label: "Blacklist", systemImage: "nosign", haptic: Haptic.destructive,
                                   hint: "Choose this place or all of its kind") { showBlockOptions = true }
                    }
                    Spacer(minLength: 6)
                    SharePickButton(place: place, context: .place) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 56, height: 56)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous).strokeBorder(Theme.hairline))
                    }
                    .accessibilityLabel("Share")
                }
                .sensoryFeedback(Haptic.tick, trigger: refresh)

                Button {
                    PlaceLinks.openDirections(place)
                    VisitFollowUp.record(place, in: context)
                } label: {
                    Label("Let’s go · directions", systemImage: "location.north.fill")
                }
                .buttonStyle(.sleekPrimary)
                .disabled(!hasDirections)
                .accessibilityLabel("Directions")
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .background(Theme.night, in: UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.sheet,
                                                                     topTrailingRadius: Theme.Radius.sheet,
                                                                     style: .continuous))
                .padding(.top, -50)

                if let onList {
                    Toggle(isOn: Binding(
                        get: { actions.isSkippedInSpins(place) },
                        set: { actions.setSkippedInSpins(place, $0); refresh += 1 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Leave out of spins")
                                .font(Theme.body(15, .semibold))
                                .foregroundStyle(Theme.text)
                            Text("Stays in your \(onList.title), but the wheel skips it.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.saffron)
                    .padding(16)
                    .card()
                    .padding(.horizontal, 20)

                    NoteField(placeID: place.id)
                        .padding(.horizontal, 20)
                }

                menuButton.padding(.horizontal, 20)

                if let address = place.address {
                    HStack(spacing: 14) {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.muted)
                        Text(address)
                            .font(Theme.body(14, .medium))
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .card()
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.night)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)  // the floating pill replaces it
        .task { if actions.saved(place)?.hasExactLocation ?? true { await loadLookAround() } }
        .sheet(isPresented: $showEdit) {
            if let record = actions.saved(place) {
                // Back to the list after saving or deleting, so nothing shows stale details.
                CustomPlaceForm(existing: record) { dismiss() }
            }
        }
        .sheet(item: $browserURL) { SafariView(url: $0).ignoresSafeArea() }
        .confirmationDialog("Add to your blacklist?", isPresented: $showBlockOptions, titleVisibility: .visible) {
            Button("Just \(place.name)", role: .destructive) {
                actions.block(place)
                dismiss()
            }
            Button("All \(place.category) places", role: .destructive) {
                actions.blockCategory(place.category)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var hero: some View {
        ZStack(alignment: .bottomTrailing) {
            if let lookAround {
                LookAroundPreview(initialScene: lookAround)
            } else {
                Map(initialPosition: .region(MKCoordinateRegion(center: place.coordinate,
                                                                latitudinalMeters: 400,
                                                                longitudinalMeters: 400))) {
                    Marker(place.name, systemImage: "fork.knife", coordinate: place.coordinate)
                        .tint(Theme.saffron)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(height: 340)
    }

    private var menuButton: some View {
        Button {
            browserURL = place.websiteURL
        } label: {
            SleekRow(systemImage: "menucard", title: "View menu & hours",
                     subtitle: place.websiteURL == nil ? "No website listed" : "Opens their website in the app")
        }
        .buttonStyle(.pressable)
        .disabled(place.websiteURL == nil)
        .opacity(place.websiteURL == nil ? 0.5 : 1)
    }

    private func loadLookAround() async {
        let request = MKLookAroundSceneRequest(coordinate: place.coordinate)
        lookAround = try? await request.scene
    }
}

/// Your own note on a saved place ("get the spicy miso", "cash only").
private struct NoteField: View {
    let placeID: String
    @Query private var matches: [SavedPlace]
    @State private var text = ""
    @FocusState private var focused: Bool

    init(placeID: String) {
        self.placeID = placeID
        _matches = Query(filter: #Predicate<SavedPlace> { $0.placeID == placeID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your note", systemImage: "note.text")
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.muted)
            TextField("Get the spicy miso, cash only…", text: $text, axis: .vertical)
                .font(Theme.body(15))
                .foregroundStyle(Theme.text)
                .lineLimit(1...5)
                .focused($focused)
                .onChange(of: focused) { if !focused { save() } }
                .onSubmit(save)
        }
        .padding(14)
        .card()
        .onAppear { text = matches.first?.note ?? "" }
        .onDisappear(perform: save)
    }

    private func save() {
        guard let item = matches.first else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if item.note != trimmed { item.note = trimmed }
    }
}
