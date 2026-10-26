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

    private let maxOptions = 6

    private var favorites: [Place] { filtered(SharedCache.loadFavorites()) }
    private var interested: [Place] { filtered(SharedCache.loadInterested()) }
    private var nearby: [Place] {
        let ids = Set((favorites + interested).map(\.id))
        return filtered(SharedCache.loadNearby()).filter { !ids.contains($0.id) }
    }

    private func filtered(_ places: [Place]) -> [Place] {
        Randomizer.eligible(places, rules: Randomizer.Rules(excludeFastFood: Preferences.excludeFastFood))
    }

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
                    if favorites.isEmpty && interested.isEmpty && nearby.isEmpty {
                        Text("Open ForkRoad and look around nearby first. Places you see there show up here.")
                            .foregroundStyle(Theme.muted)
                            .listRowBackground(Color.clear)
                    }
                    section("Favorites", favorites)
                    section("Want to try", interested)
                    section("Nearby", nearby)
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

    @ViewBuilder
    private func section(_ title: String, _ places: [Place]) -> some View {
        if !places.isEmpty {
            Section(title) {
                ForEach(places) { place in
                    let isOn = selected.contains(place)
                    Button {
                        if let i = selected.firstIndex(of: place) { selected.remove(at: i) }
                        else if selected.count < maxOptions { selected.append(place) }
                    } label: {
                        HStack(spacing: 12) {
                            MonogramTile(name: place.name, category: place.category, size: 34)
                            Text(place.name).foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isOn ? Theme.accentText : Theme.muted.opacity(0.5))
                        }
                    }
                    .disabled(!isOn && selected.count >= maxOptions)
                }
            }
            .listRowBackground(Theme.surface)
        }
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
                        Button { state.expand(); showAdd = true } label: {
                            Label(session.mode == .spin ? "Add your pick" : "Suggest a place", systemImage: "plus.circle.fill")
                                .font(Theme.body(15, .bold))
                                .foregroundStyle(Theme.accentText)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(session.options.count >= 12)
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

/// Add a place to a vote from the iMessage app (your saved places and last nearby search).
struct MessageAddPlaceView: View {
    let session: GroupSession
    @Environment(\.dismiss) private var dismiss
    @State private var adding: String?
    @State private var errorMessage: String?

    private var candidates: [(String, [Place])] {
        let taken = Set(session.options.map(\.id))
        let rules = SharedCache.pickRules()
        func clean(_ places: [Place]) -> [Place] {
            Randomizer.eligible(places, rules: rules).filter { !taken.contains($0.id) }
        }
        let favorites = clean(SharedCache.loadFavorites())
        let interested = clean(SharedCache.loadInterested())
        let savedIDs = Set((favorites + interested).map(\.id))
        let nearby = clean(SharedCache.loadNearby()).filter { !savedIDs.contains($0.id) }
        return [("Favorites", favorites), ("Want to try", interested), ("Nearby", nearby)].filter { !$0.1.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger).listRowBackground(Color.clear)
                }
                if candidates.isEmpty {
                    Text("Open ForkRoad and look around nearby (or search) first. Places you see there show up here.")
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Color.clear)
                }
                ForEach(candidates, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { place in
                            Button { add(place) } label: {
                                HStack(spacing: 12) {
                                    MonogramTile(name: place.name, category: place.category, size: 34)
                                    Text(place.name).foregroundStyle(Theme.text)
                                    Spacer()
                                    if adding == place.id { ProgressView() }
                                    else { Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentText) }
                                }
                            }
                            .disabled(adding != nil)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
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
            } catch {
                errorMessage = "Couldn’t add it. Voting may have closed, or the list is full."
            }
        }
    }
}
