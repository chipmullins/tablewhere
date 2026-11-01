import SwiftUI
import SwiftData
import PickerCore

/// Sheet for starting a group plan: name it, choose vote, spin, or "I'll
/// pick" (you already know where: set the time and send it), pick places.
struct CreateGroupView: View {
    var onCreated: (GroupSession) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]

    @State private var title = ""
    @State private var mode: GroupMode = .vote
    @State private var closesIn: Int? = nil
    @State private var selected: [Place] = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var query = ""
    /// The search field is open. On iOS 26 it covers the nav bar (and Start),
    /// so a spin pick closes it and the bottom bar has its own Start.
    @State private var isSearching = false
    /// An area picked in the place picker; saved on the plan for everyone.
    @State private var pickedArea: PickerArea?
    @State private var startTaps = 0
    // "I'll pick"
    @State private var meetTime = PlanSetupRows.defaultMeetTime()
    @State private var note = ""
    @State private var asksRSVP = false
    @State private var hasReplyBy = false
    @State private var replyBy = PlanSetupRows.defaultReplyBy(for: PlanSetupRows.defaultMeetTime())

    static let maxVoteOptions = GroupMode.maxStartingVoteOptions
    /// In a spin everyone adds one place, starting with you; a plan has one.
    private var maxOptions: Int { mode == .vote ? Self.maxVoteOptions : 1 }
    private var isSingle: Bool { mode != .vote }

    private var rules: Randomizer.Rules {
        model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories)
    }
    private func savedPlaces(in list: SavedList) -> [Place] {
        saved.filter { $0.list == list && $0.isShareable }.map { $0.asPlace(from: model.center) }
    }

    var body: some View {
        NavigationStack {
            Form {
                modeSection

                if !selected.isEmpty {
                    Section(mode == .plan ? "The place" : "Picked (\(selected.count))") {
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

                if mode == .plan {
                    PlanSetupRows(meetTime: $meetTime, note: $note, asksRSVP: $asksRSVP,
                                  hasReplyBy: $hasReplyBy, replyBy: $replyBy)
                }

                GroupPlacePicker(
                    query: query,
                    center: model.center,
                    centerName: model.locationName,
                    favorites: savedPlaces(in: .favorites),
                    interested: savedPlaces(in: .interested),
                    startingFilters: PlacePickerFilters(model.searchArea),
                    startingNearby: model.places,
                    rules: rules,
                    search: model.placeSearch,
                    accessory: { .check(isOn: selected.contains($0)) },
                    isDisabled: { mode == .vote && !selected.contains($0) && selected.count >= maxOptions },
                    onAreaChange: { pickedArea = $0 },
                    onTap: toggle
                )

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                        .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .searchable(text: $query, isPresented: $isSearching,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search restaurants or cravings")
            // Don't lose your picks to a stray swipe.
            .interactiveDismissDisabled(!selected.isEmpty)
            .sensoryFeedback(Haptic.commit, trigger: startTaps)
            .navigationTitle("New group plan")
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
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .presentationBackground(Theme.night)
    }

    /// Name, and how the group decides.
    private var modeSection: some View {
        Section {
            TextField("Name (\(mode.defaultTitle))", text: $title)
            Picker("Who picks", selection: $mode) {
                Text("Vote").tag(GroupMode.vote)
                Text("Spin").tag(GroupMode.spin)
                Text("I’ll pick").tag(GroupMode.plan)
            }
            .pickerStyle(.segmented)
            .sensoryFeedback(Haptic.tick, trigger: mode)
            .onChange(of: mode) {
                if isSingle && selected.count > 1 { selected = Array(selected.prefix(1)) }
            }
            if mode == .vote {
                Picker("Voting closes", selection: $closesIn) {
                    Text("When I lock it in").tag(Int?.none)
                    Text("In 5 min").tag(Int?.some(5))
                    Text("In 15 min").tag(Int?.some(15))
                    Text("In 30 min").tag(Int?.some(30))
                }
            }
        } footer: {
            Text(modeFooter)
        }
        .listRowBackground(Theme.surface)
    }

    private var modeFooter: String {
        switch mode {
        case .vote:
            return "Start with 2–\(Self.maxVoteOptions) places (you can add more later, up to \(GroupSession.maxOptions)). Everyone else can suggest one. Most votes wins; ties are broken fairly."
        case .spin:
            return "Everyone adds one place, starting with you. Then you spin and the app picks one at random."
        case .plan:
            return "You choose the place and time. Everyone gets the plan, and can say if they’re in if you ask."
        }
    }

    private var pickedLine: String {
        switch mode {
        case .vote: return "\(selected.count) of up to \(maxOptions) selected"
        case .spin: return selected.first.map { "Your pick: \($0.name)" } ?? "Pick your one place for the wheel"
        case .plan: return selected.first.map { "\($0.name) · \(MeetTimes.label(for: meetTime))" } ?? "Pick the place"
        }
    }

    private var startTitle: String {
        switch mode {
        case .vote: return "Start the vote"
        case .spin: return "Start the spin"
        case .plan: return "Send the plan"
        }
    }

    /// What's picked, and a Start that's always reachable (even mid-search).
    private var bottomBar: some View {
        VStack(spacing: 8) {
            Text(pickedLine)
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            if canCreate {
                Button { create() } label: {
                    HStack(spacing: 8) {
                        if isCreating { ProgressView().tint(Theme.onSaffron) }
                        Text(startTitle)
                    }
                    .font(Theme.display(17))
                    .foregroundStyle(Theme.onSaffron)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isCreating)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.night)
        .animation(.snappy, value: canCreate)
    }

    private var canCreate: Bool {
        switch mode {
        case .vote: return selected.count >= 2
        case .spin: return selected.count >= 1
        case .plan: return selected.count == 1 && meetTime.timeIntervalSinceNow > 0
        }
    }

    /// What you typed, or the default name.
    private var groupTitle: String {
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? mode.defaultTitle : String(typed.prefix(60))
    }

    private func toggle(_ place: Place) {
        if let index = selected.firstIndex(of: place) {
            selected.remove(at: index)
        } else if isSingle {
            selected = [place]  // one pick: tapping another swaps it
            // That's your one pick: close the search so you can see it and Start.
            query = ""
            isSearching = false
        } else if selected.count < maxOptions {
            selected.append(place)
        }
    }

    /// Where everyone else's picker starts: the area you picked here, else
    /// where you're searching. ("Near you" would mean them, so it gets a real name.)
    private func groupArea(creatorName: String) -> GroupArea? {
        if let pickedArea { return pickedArea.groupArea }
        guard model.hasLocation else { return nil }
        let name = model.isUsingCurrentLocation
            ? (model.location.placeName ?? model.currentCity ?? "\(creatorName)’s area")
            : model.locationName
        return GroupArea(name: name, latitude: model.center.latitude, longitude: model.center.longitude)
    }

    private func create() {
        guard let name = Identity.displayName else { return }
        startTaps += 1
        isCreating = true
        errorMessage = nil
        Task {
            defer { isCreating = false }
            do {
                let session = try await GroupService.shared.createSession(
                    title: groupTitle,
                    mode: mode,
                    options: selected.map { GroupOption(place: $0, addedBy: name) },
                    closesInMinutes: mode == .vote ? closesIn : nil,
                    displayName: name,
                    area: groupArea(creatorName: name),
                    meetTime: mode == .plan ? meetTime : nil,
                    note: mode == .plan ? note : nil,
                    asksRSVP: mode == .plan && asksRSVP,
                    rsvpBy: mode == .plan && asksRSVP && hasReplyBy ? PlanSetupRows.clampedReplyBy(replyBy, meetTime: meetTime) : nil
                )
                onCreated(session)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
