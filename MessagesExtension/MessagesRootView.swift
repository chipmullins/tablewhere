import SwiftUI
import Messages
import PickerCore

/// Chooses what the extension shows: setup, name prompt, a vote, or "new vote".
struct MessagesRootView: View {
    @Bindable var state: MessagesState
    @State private var hasName = Identity.displayName != nil

    var body: some View {
        Group {
            if !FirebaseSetup.isConfigured {
                notice("Open ForkRoad to finish setting up group voting.")
            } else if !hasName {
                if state.isExpanded {
                    NamePromptView { _ in hasName = true }
                } else {
                    startButton(title: "Set up ForkRoad voting") { state.expand() }
                }
            } else if let sessionID = state.sessionID {
                MessageVoteView(sessionID: sessionID, state: state)
                    .id(sessionID)
            } else {
                NewVoteView(state: state)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.night)
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(15, .semibold))
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.display(18))
                .foregroundStyle(Theme.onSaffron)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(16)
    }
}

/// Pick places from your Favorites, Interested list, and last nearby search, then send a vote.
struct NewVoteView: View {
    @Bindable var state: MessagesState

    @State private var selected: [Place] = []
    @State private var includeWebLink = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var query = ""
    @AppStorage(Preferences.noFastFoodKey, store: SharedDefaults.store) private var excludeFastFood = false

    private let maxOptions = 6

    var body: some View {
        if !state.isExpanded {
            Button { state.expand() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(Theme.body(18, .bold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 44, height: 44)
                        .background(Theme.onSaffron, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start a dinner vote").font(Theme.display(18))
                        Text("Pick a few places, friends vote right here").font(Theme.body(12, .medium))
                    }
                    Spacer()
                }
                .foregroundStyle(Theme.onSaffron)
                .padding(14)
                .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(16)
        } else {
            VStack(spacing: 0) {
                List {
                    Section {
                        MessageSearchField(text: $query)
                    }
                    .listRowBackground(Theme.surface)
                    if !selected.isEmpty {
                        Section("Picked (\(selected.count) of \(maxOptions))") {
                            ForEach(selected) { place in
                                Button { toggle(place) } label: {
                                    HStack(spacing: 12) {
                                        MonogramTile(name: place.name, category: place.category, size: 30)
                                        Text(place.name).foregroundStyle(Theme.text).lineLimit(1)
                                        Spacer()
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                    MessagePlacePicker(query: query, excludeFastFood: excludeFastFood,
                                       accessory: { .check(isOn: selected.contains($0)) },
                                       isDisabled: { !selected.contains($0) && selected.count >= maxOptions },
                                       onTap: toggle)
                    Section {
                        Toggle("Also send a web link for friends without ForkRoad", isOn: $includeWebLink)
                            .tint(Theme.saffron)
                    }
                    .listRowBackground(Theme.surface)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(Theme.danger).listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)

                Button(action: send) {
                    Group {
                        if isSending { ProgressView().tint(Theme.onSaffron) }
                        else { Text(selected.count < 2 ? "Pick at least 2 places" : "Send vote · \(selected.count) places") }
                    }
                    .font(Theme.display(17))
                    .foregroundStyle(Theme.onSaffron)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Theme.saffron.opacity(selected.count < 2 ? 0.45 : 1),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(selected.count < 2 || isSending)
                .padding(16)
            }
        }
    }

    private func toggle(_ place: Place) {
        if let i = selected.firstIndex(of: place) { selected.remove(at: i) }
        else if selected.count < maxOptions { selected.append(place) }
    }

    private func send() {
        guard let name = Identity.displayName else { return }
        isSending = true
        errorMessage = nil
        Task {
            defer { isSending = false }
            do {
                let session = try await GroupService.shared.createSession(
                    title: "Where should we eat?",
                    mode: .vote,
                    options: selected.map { GroupOption(place: $0, addedBy: name) },
                    closesInMinutes: nil,
                    displayName: name
                )
                state.insertNewVote(session, includeWebLink: includeWebLink)
                selected = []
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// A live vote opened from a bubble.
struct MessageVoteView: View {
    let sessionID: String
    @Bindable var state: MessagesState
    @State private var live: LiveSession
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showAdd = false
    @State private var confirmEnd = false

    init(sessionID: String, state: MessagesState) {
        self.sessionID = sessionID
        self.state = state
        _live = State(initialValue: LiveSession(sessionID: sessionID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let session = live.session {
                    HStack {
                        Text(session.title)
                            .font(Theme.display(20))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Button("New vote") { state.showNewVote() }
                            .font(Theme.body(13, .semibold))
                            .foregroundStyle(Theme.accentText)
                    }

                    if let winner = session.winner {
                        WinnerCard(option: winner,
                                   detail: session.meetTime.map { "Meet at \($0.formatted(date: .omitted, time: .shortened))" } ?? winner.category)
                        if let url = directionsURL(winner) {
                            Button { state.open(url: url) } label: {
                                Label("Directions", systemImage: "location.north.line")
                                    .font(Theme.body(15, .bold))
                                    .foregroundStyle(Theme.night)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Theme.text, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        if let note = session.trimmedNote {
                            PlanNoteCard(note: note, author: session.createdByName)
                        }
                        if session.mode == .vote {
                            VoteBreakdown(options: session.options,
                                          tally: live.tally,
                                          winnerID: session.winnerID,
                                          nonVoters: live.nonVoterNames)
                        }
                    } else {
                        let tally = live.tally
                        let slots = max(live.members.count, tally.totalVotes, 1)
                        ForEach(session.options) { option in
                            VoteOptionRow(option: option,
                                          votes: tally.count(for: option.id),
                                          totalSlots: slots,
                                          voters: tally.votersByOption[option.id] ?? [],
                                          isMine: live.myVote == option.id,
                                          isLeading: tally.leader == option.id,
                                          isEnabled: !isWorking && session.mode == .vote,
                                showsVotes: session.mode == .vote) {
                                vote(option, session: session)
                            }
                        }
                        AddPlaceButton(session: session, userID: GroupService.shared.currentUserID) {
                            state.expand(); showAdd = true
                        }
                        if live.isOwner {
                            Button { lockIn(session) } label: {
                                Text("Lock it in")
                                    .font(Theme.display(17))
                                    .foregroundStyle(Theme.onSaffron)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking || (session.mode == .vote && tally.totalVotes == 0))
                        }
                    }
                    Button(live.isOwner ? "End group for everyone" : "Leave group", role: .destructive) {
                        if live.isOwner { confirmEnd = true } else { leave() }
                    }
                    .font(Theme.body(13, .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    if let errorMessage {
                        Text(errorMessage).font(Theme.body(13)).foregroundStyle(Theme.danger)
                    }
                } else if live.errorMessage != nil {
                    Text("This group pick has ended.")
                        .font(Theme.body(15, .semibold))
                        .foregroundStyle(Theme.muted)
                    Button("Start a new vote") { state.showNewVote() }
                        .font(Theme.body(15, .bold))
                        .foregroundStyle(Theme.accentText)
                } else {
                    ProgressView().tint(Theme.muted).frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(16)
        }
        .task {
            await live.start()
            if let name = Identity.displayName {
                try? await GroupService.shared.join(sessionID: sessionID, displayName: name)
            }
        }
        .onChange(of: live.session?.status) {
            if live.session?.status == .decided { state.expand() }
        }
        .sheet(isPresented: $showAdd) {
            if let session = live.session { MessageAddPlaceView(session: session) }
        }
        .confirmationDialog("End this group pick?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End for everyone", role: .destructive) { end() }
        }
    }

    private func end() {
        guard let session = live.session else { return }
        Task {
            do {
                live.stop()
                try await GroupService.shared.endSession(session)
                state.showNewVote()
            } catch {
                errorMessage = error.localizedDescription
                await live.start()
            }
        }
    }

    private func leave() {
        Task {
            do {
                try await GroupService.shared.leaveSession(sessionID)
                state.showNewVote()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func vote(_ option: GroupOption, session: GroupSession) {
        guard let name = Identity.displayName else {
            errorMessage = "Open ForkRoad and add your name to vote."
            return
        }
        if !state.isExpanded { state.expand() }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                if live.myVote == option.id {
                    try await GroupService.shared.removeVote(sessionID: session.id)
                } else {
                    try await GroupService.shared.vote(sessionID: session.id, optionID: option.id, displayName: name)
                }
                // The live tally updates here. We don't post a new bubble per
                // vote, so the group isn't notified for every tap; the bubble
                // updates once, when the result is locked in.
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func lockIn(_ session: GroupSession) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                if let winnerID = try await GroupService.shared.decide(session: session, votes: live.votes) {
                    // Send right away (still part of the tap) rather than waiting
                    // for the listener, so Messages treats it as a user action.
                    var decided = session
                    decided.status = .decided
                    decided.winnerID = winnerID
                    state.sendUpdate(decided, tally: live.tally, memberCount: live.members.count)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func directionsURL(_ option: GroupOption) -> URL? {
        let name = option.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?daddr=\(option.latitude),\(option.longitude)&q=\(name)")
    }
}

/// Add a place to a vote from the iMessage app, with Discover's filters and search.
struct MessageAddPlaceView: View {
    let session: GroupSession
    @Environment(\.dismiss) private var dismiss
    @State private var adding: String?
    @State private var errorMessage: String?
    @State private var query = ""
    @AppStorage(Preferences.noFastFoodKey, store: SharedDefaults.store) private var excludeFastFood = false

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger).listRowBackground(Color.clear)
                }
                MessagePlacePicker(query: query, excludeFastFood: excludeFastFood,
                                   excludedIDs: Set(session.options.map(\.id)),
                                   accessory: { .add(isBusy: adding == $0.id) },
                                   isDisabled: { _ in adding != nil },
                                   onTap: add)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search restaurants or cravings")
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func add(_ place: Place) {
        adding = place.id
        Task {
            defer { adding = nil }
            do {
                try await GroupService.shared.addOption(
                    sessionID: session.id,
                    option: GroupOption(place: place, addedBy: Identity.displayName ?? "Someone"))
                dismiss()
            } catch let error as GroupError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Couldn’t add it. Voting may have closed, or the list is full."
            }
        }
    }
}

/// The group place picker fed from what the app shares with the extension:
/// saved lists, the last nearby results, and where the app last searched.
struct MessagePlacePicker: View {
    let query: String
    let excludeFastFood: Bool
    var excludedIDs: Set<String> = []
    let accessory: (Place) -> PlacePickerAccessory
    var isDisabled: (Place) -> Bool = { _ in false }
    let onTap: (Place) -> Void

    // Read once per sheet, not on every redraw.
    @State private var area = SharedCache.loadSearchArea()
    @State private var favorites = SharedCache.loadFavorites()
    @State private var interested = SharedCache.loadInterested()
    @State private var nearby = SharedCache.loadNearby()

    private var rules: Randomizer.Rules {
        var rules = SharedCache.pickRules()
        rules.excludeFastFood = excludeFastFood
        return rules
    }

    var body: some View {
        GroupPlacePicker(
            query: query,
            center: area?.center,
            favorites: favorites,
            interested: interested,
            startingFilters: area.map { PlacePickerFilters($0) } ?? PlacePickerFilters(),
            startingNearby: nearby,
            rules: rules,
            excludedIDs: excludedIDs,
            accessory: accessory,
            isDisabled: isDisabled,
            onTap: onTap
        )
    }
}

/// A plain search field (the iMessage drawer has no navigation bar for `.searchable`).
struct MessageSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Search restaurants or cravings", text: $text)
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
    }
}

/// The iMessage extension's "No fast food" chip (the app's reads AppModel).
/// Same saved setting, so the app and extension stay in sync.
struct NoFastFoodChip: View {
    @AppStorage(Preferences.noFastFoodKey, store: SharedDefaults.store) private var excludeFastFood = false

    var body: some View {
        FastFoodChip(isOn: $excludeFastFood)
    }
}
