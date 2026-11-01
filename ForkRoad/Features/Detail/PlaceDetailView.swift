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
                    .frame(height: 260)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(place.name)
                        .font(Theme.display(32))
                        .foregroundStyle(Theme.text)
                    Text(isCustom
                         ? (hasDirections ? "\(place.category) · \(place.distanceLabel) · added by you"
                                          : "\(place.category) · added by you · no address")
                         : "\(place.category) · \(place.distanceLabel)")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16)

                HStack(spacing: 8) {
                    ActionTile(title: "Call", systemImage: "phone", tint: Theme.accentText, background: Theme.surface) {
                        if let url = PlaceLinks.phoneURL(place) { openURL(url) }
                    }
                    .disabled(place.phoneNumber == nil)
                    .opacity(place.phoneNumber == nil ? 0.4 : 1)

                    ActionTile(title: "Go", systemImage: "location.north.line", tint: Theme.accentText, background: Theme.surface) {
                        PlaceLinks.openDirections(place)
                        VisitFollowUp.record(place, in: context)
                    }
                    .disabled(!hasDirections)
                    .opacity(hasDirections ? 1 : 0.4)

                    ActionTile(title: "Favorite",
                               systemImage: onList == .favorites ? "heart.fill" : "heart",
                               tint: onList == .favorites ? Theme.onSaffron : Theme.text,
                               background: onList == .favorites ? Theme.saffron : Theme.surface,
                               isOn: onList == .favorites) {
                        actions.toggle(place, in: .favorites)
                        refresh += 1
                    }

                    ActionTile(title: "Try",
                               systemImage: onList == .interested ? "bookmark.fill" : "bookmark",
                               tint: onList == .interested ? Theme.onSaffron : Theme.text,
                               background: onList == .interested ? Theme.saffron : Theme.surface,
                               isOn: onList == .interested) {
                        actions.toggle(place, in: .interested)
                        refresh += 1
                    }

                    if isCustom {
                        ActionTile(title: "Edit", systemImage: "pencil", background: Theme.surface) {
                            showEdit = true
                        }
                    } else {
                        ActionTile(title: "Blacklist", systemImage: "nosign", background: Theme.surface) {
                            showBlockOptions = true
                        }
                    }
                }
                .padding(.horizontal, 16)
                .sensoryFeedback(.impact(weight: .light), trigger: refresh)

                if let onList {
                    Toggle(isOn: Binding(
                        get: { actions.isSkippedInSpins(place) },
                        set: { actions.setSkippedInSpins(place, $0); refresh += 1 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Leave out of spins")
                                .font(Theme.body(15, .semibold))
                                .foregroundStyle(Theme.text)
                            Text("Stays in your \(onList.title), but the dice skips it.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.saffron)
                    .padding(14)
                    .card()
                    .padding(.horizontal, 16)

                    NoteField(placeID: place.id)
                        .padding(.horizontal, 16)
                }

                menuButton.padding(.horizontal, 16)

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
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.night)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
        .frame(height: 300)
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, Theme.night], startPoint: .top, endPoint: .bottom)
                .frame(height: 80)
                .allowsHitTesting(false)
        }
    }

    private var menuButton: some View {
        Button {
            browserURL = place.websiteURL
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "menucard")
                    .font(Theme.body(20, .semibold))
                    .foregroundStyle(Theme.onSaffron)
                    .frame(width: 44, height: 44)
                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("View menu & hours").font(Theme.display(16)).foregroundStyle(Theme.text)
                    Text(place.websiteURL == nil ? "No website listed" : "Opens their website in the app")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(Theme.muted)
            }
            .padding(14)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.saffron.opacity(0.35)))
        }
        .buttonStyle(.plain)
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
