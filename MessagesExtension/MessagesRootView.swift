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

    @State private var mode: GroupMode = .vote
    @State private var title = ""
    @State private var closesIn: Int? = nil

    /// A vote starts with 2–6 of your places; a spin starts with your one pick.
    private var maxOptions: Int { mode == .spin ? 1 : 6 }
    private var minOptions: Int { mode == .spin ? 1 : 2 }
    private var canSend: Bool { selected.count >= minOptions && !isSending }

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
                        Text("Start a dinner pick").font(Theme.display(18))
                        Text("Vote on a few places, or everyone adds one and you spin").font(Theme.body(12, .medium))
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
                        Picker("How to decide", selection: $mode) {
                            Text("Vote").tag(GroupMode.vote)
                            Text("Spin").tag(GroupMode.spin)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) {
                            if mode == .spin && selected.count > 1 { selected = Array(selected.prefix(1)) }
                        }
                        TextField(mode == .spin ? "Name (Spin for dinner)" : "Name (Where should we eat?)", text: $title)
                            .foregroundStyle(Theme.text)
                            .submitLabel(.done)
                        if mode == .vote {
                            Picker("Voting closes", selection: $closesIn) {
                                Text("When I lock it in").tag(Int?.none)
                                Text("In 5 min").tag(Int?.some(5))
                                Text("In 15 min").tag(Int?.some(15))
                                Text("In 30 min").tag(Int?.some(30))
                            }
                            .tint(Theme.accentText)
                        }
                    } footer: {
                        Text(mode == .vote
                             ? "Pick 2–6 places. Friends vote and can each suggest one more. Most votes wins."
                             : "Pick your one place. Everyone adds theirs, then you spin and the app picks one at random.")
                    }
                    .listRowBackground(Theme.surface)
                    Section {
                        MessageSearchField(text: $query)
                    }
                    .listRowBackground(Theme.surface)
                    if !selected.isEmpty {
                        Section(mode == .spin ? "Your pick" : "Picked (\(selected.count) of \(maxOptions))") {
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
                                       isDisabled: { mode == .vote && !selected.contains($0) && selected.count >= maxOptions },
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
                        else { Text(sendTitle) }
                    }
                    .font(Theme.display(17))
                    .foregroundStyle(Theme.onSaffron)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Theme.saffron.opacity(canSend ? 1 : 0.45),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .padding(16)
            }
        }
    }

    /// What you typed, or the default name.
    private var groupTitle: String {
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return String(typed.prefix(60)) }
        return mode == .spin ? "Spin for dinner" : "Where should we eat?"
    }

    private var sendTitle: String {
        switch mode {
        case .vote: return selected.count < 2 ? "Pick at least 2 places" : "Send vote · \(selected.count) places"
        case .spin: return selected.first.map { "Start the spin · \($0.name)" } ?? "Pick your place"
        }
    }

    private func toggle(_ place: Place) {
        if let i = selected.firstIndex(of: place) { selected.remove(at: i) }
        else if mode == .spin { selected = [place] }  // one pick: tapping another swaps it
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
                    title: groupTitle,
                    mode: mode,
                    options: selected.map { GroupOption(place: $0, addedBy: name) },
                    closesInMinutes: mode == .vote ? closesIn : nil,
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
    @State private var removing: GroupOption?
    @State private var reveal: GroupOption?

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
                        if live.isOwner {
                            MessagePlanControls(session: session) { updated in
                                // A new bubble so the chat shows "Meet at 7:00 PM".
                                state.sendUpdate(updated, tally: live.tally, memberCount: live.members.count)
                            }
                        } else if let note = session.trimmedNote {
                            PlanNoteCard(note: note, author: session.createdByName)
                        }
                        if let meet = session.meetTime, meet > .now.addingTimeInterval(-15 * 60) {
                            AddToCalendarButton(session: session, winner: winner, meetTime: meet)
                            LeaveByCard(sessionID: session.id, winner: winner, meetTime: meet,
                                        origin: { await MessageLeaveOrigin.current() },
                                        askForLocation: { await OneShotLocation.shared.requestPermission() })
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
                        let ruledOut = live.ruledOutIDs
                        if session.mode == .spin {
                            SpinProgressLine(waiting: live.waitingOnPicks, memberCount: live.members.count)
                        }
                        ForEach(session.options) { option in
                            VoteOptionRow(option: option,
                                          votes: tally.count(for: option.id),
                                          totalSlots: slots,
                                          voters: tally.votersByOption[option.id] ?? [],
                                          isMine: live.myVote == option.id,
                                          isLeading: tally.leader == option.id,
                                          isEnabled: !isWorking && session.mode == .vote && !ruledOut.contains(option.id),
                                          showsVotes: session.mode == .vote,
                                          isRuledOut: ruledOut.contains(option.id)) {
                                vote(option, session: session)
                            }
                        }
                        AddPlaceButton(session: session, userID: GroupService.shared.currentUserID) {
                            state.expand(); showAdd = true
                        }
                        if live.isOwner {
                            OwnerGroupTools(session: session,
                                            nudge: Nudge.text(session: session, members: live.members, votes: live.votes),
                                            sendNudge: { state.insertText($0) },
                                            onRemove: { removing = $0 })
                        }
                        if live.isOwner {
                            Button { lockIn(session) } label: {
                                Text(session.mode == .spin ? "Spin it" : "Lock it in")
                                    .font(Theme.display(17))
                                    .foregroundStyle(Theme.onSaffron)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking || session.options.isEmpty || (session.mode == .vote && tally.totalVotes == 0))
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
        // A timed vote locks itself in when time's up, if the creator has it open.
        .task(id: live.session?.closesAt) { await autoCloseWhenTimeIsUp() }
        .onChange(of: live.session?.status) { old, new in
            guard new == .decided else { return }
            state.expand()
            // Everyone watching a Group Spin sees the wheel land.
            if old == .open, let session = live.session, session.mode == .spin, let winner = session.winner {
                reveal = winner
            }
        }
        .overlay {
            if let reveal, let session = live.session {
                SpinReveal(names: session.options.map(\.name), winner: reveal.name) { self.reveal = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: reveal?.id)
        .confirmationDialog("Remove \(removing?.name ?? "this place")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) { removePlace() }
        } message: {
            Text("Its votes are cleared, and whoever added it can add a different place.")
        }
        .sheet(isPresented: $showAdd) {
            if let session = live.session {
                MessageAddPlaceView(session: session, groupBlockedHashes: live.groupBlockedHashes)
            }
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

    private func autoCloseWhenTimeIsUp() async {
        guard let session = live.session, let closesAt = session.closesAt,
              session.status == .open, live.isOwner else { return }
        let wait = closesAt.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        guard !Task.isCancelled, let current = live.session, current.status == .open else { return }
        _ = try? await GroupService.shared.decide(session: current, votes: live.votes, ruledOut: live.ruledOutIDs)
    }

    private func removePlace() {
        guard let option = removing, let session = live.session else { return }
        removing = nil
        Task {
            do { try await GroupService.shared.removeOption(option.id, from: session) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func lockIn(_ session: GroupSession) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                if let winnerID = try await GroupService.shared.decide(session: session, votes: live.votes,
                                                                       ruledOut: live.ruledOutIDs) {
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
    var groupBlockedHashes: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    @State private var adding: String?
    @State private var errorMessage: String?
    @State private var query = ""
    @AppStorage(Preferences.noFastFoodKey, store: SharedDefaults.store) private var excludeFastFood = false

    /// You already picked, so choosing a place swaps it.
    private var isChanging: Bool {
        guard let uid = GroupService.shared.currentUserID else { return false }
        return session.pick(of: uid) != nil && !(session.mode == .vote && session.isOwned(by: uid))
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger).listRowBackground(Color.clear)
                }
                MessagePlacePicker(query: query, excludeFastFood: excludeFastFood,
                                   excludedIDs: Set(session.options.map(\.id)),
                                   groupBlockedHashes: groupBlockedHashes,
                                   sessionID: session.id,
                                   accessory: { .add(isBusy: adding == $0.id) },
                                   isDisabled: { _ in adding != nil },
                                   onTap: add)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search restaurants or cravings")
            .navigationTitle(isChanging ? "Change your pick" : "Add a place")
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
    var groupBlockedHashes: Set<String> = []
    var sessionID: String?
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
            groupBlockedHashes: groupBlockedHashes,
            sessionID: sessionID,
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


/// For the group's creator once it's decided: pick the meeting time (quick
/// quarter-hour slots or any time) and add a short note, like in the app.
struct MessagePlanControls: View {
    let session: GroupSession
    /// Sends an updated bubble after the time changes.
    var onTimeSet: (GroupSession) -> Void

    @State private var showPicker = false
    @State private var noteDraft = ""
    @State private var savingNote = false
    @State private var errorMessage: String?
    @FocusState private var noteFocused: Bool

    var body: some View {
        let slots = MeetTimes.slots(count: 6)
        let isSlot: (Date) -> Bool = { slot in
            session.meetTime.map { abs($0.timeIntervalSince(slot)) < 60 } ?? false
        }
        let isCustom = session.meetTime != nil && !slots.contains(where: isSlot)

        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: session.meetTime == nil ? "Set a meeting time" : "Meet at")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(slots, id: \.self) { slot in
                    timeButton(slot.formatted(date: .omitted, time: .shortened), isOn: isSlot(slot)) { setTime(slot) }
                }
            }
            timeButton(isCustom ? "Custom: \(session.meetTime?.formatted(date: .omitted, time: .shortened) ?? "")" : "Pick another time…",
                       isOn: isCustom) { showPicker = true }

            SectionLabel(text: "Note for the group")
                .padding(.top, 6)
            HStack(spacing: 8) {
                TextField("Optional, like “Bring a gift!”", text: $noteDraft)
                    .font(Theme.body(15, .medium))
                    .foregroundStyle(Theme.text)
                    .focused($noteFocused)
                    .submitLabel(.done)
                    .onSubmit(saveNote)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if noteChanged {
                    Button(savingNote ? "Saving…" : "Save", action: saveNote)
                        .font(Theme.body(14, .bold))
                        .foregroundStyle(Theme.onSaffron)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .buttonStyle(.plain)
                        .disabled(savingNote)
                }
            }
            if let errorMessage {
                Text(errorMessage).font(Theme.body(13)).foregroundStyle(Theme.danger)
            }
        }
        .onAppear { noteDraft = session.note ?? "" }
        .onChange(of: noteDraft) {
            if noteDraft.count > GroupSession.maxNoteLength { noteDraft = String(noteDraft.prefix(GroupSession.maxNoteLength)) }
        }
        .sheet(isPresented: $showPicker) {
            MeetTimePickerSheet(initial: session.meetTime ?? slots.first ?? .now) { setTime($0) }
        }
    }

    private var noteChanged: Bool {
        noteDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (session.trimmedNote ?? "")
    }

    private func timeButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .font(Theme.body(14, .bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isOn ? Theme.night : Theme.text)
                .background(isOn ? Theme.text : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func setTime(_ date: Date) {
        errorMessage = nil
        var updated = session
        updated.meetTime = date
        // Send the bubble right away, while it's still part of the tap
        // (Messages only sends in response to the user), then save.
        onTimeSet(updated)
        Task {
            do { try await GroupService.shared.setMeetTime(sessionID: session.id, date: date) }
            catch { errorMessage = "Couldn’t save the time. Check your connection and try again." }
        }
    }

    private func saveNote() {
        guard noteChanged else { noteFocused = false; return }
        noteFocused = false
        savingNote = true
        errorMessage = nil
        let text = noteDraft
        Task {
            defer { savingNote = false }
            do { try await GroupService.shared.setNote(sessionID: session.id, note: text) }
            catch { errorMessage = "Couldn’t save the note. Check your connection and try again." }
        }
    }
}

/// Where the iMessage app measures leave-by from: your location if you've
/// allowed it here, else where the app last searched.
@MainActor
enum MessageLeaveOrigin {
    static func current() async -> LeaveBy.Origin? {
        if let gps = await OneShotLocation.shared.current() {
            return LeaveBy.Origin(coordinate: gps, isGPS: true, label: "where you are")
        }
        if let area = SharedCache.loadSearchArea() {
            return LeaveBy.Origin(coordinate: area.center, isGPS: false, label: "your last search area")
        }
        return nil
    }
}
