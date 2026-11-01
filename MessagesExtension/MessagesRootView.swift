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
    @State private var sendTaps = 0

    /// A vote starts with 2–8 of your places; a spin starts with your one pick.
    private var maxOptions: Int { mode == .spin ? 1 : GroupMode.maxStartingVoteOptions }
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
                        Text("Start a group plan").font(Theme.display(18))
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
                        .sensoryFeedback(Haptic.tick, trigger: mode)
                        .onChange(of: mode) {
                            if mode == .spin && selected.count > 1 { selected = Array(selected.prefix(1)) }
                        }
                        TextField("Name (\(mode.defaultTitle))", text: $title)
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
                             ? "Start with 2–\(GroupMode.maxStartingVoteOptions) places (you can add more later, up to \(GroupSession.maxOptions)). Everyone else can suggest one. Most votes wins; ties are broken fairly."
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
                .sensoryFeedback(Haptic.commit, trigger: sendTaps)
                .padding(16)
            }
        }
    }

    /// What you typed, or the default name.
    private var groupTitle: String {
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return String(typed.prefix(60)) }
        return mode.defaultTitle
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
        sendTaps += 1
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
                errorMessage = GroupService.message(for: error)
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
    @State private var confirmLeave = false
    @State private var confirmLockIn = false
    @State private var removing: GroupOption?
    /// Bumped when a vote's timer runs out, so the view switches to "closed".
    @State private var timeUpTick = 0
    /// Bumped after posting a bubble, so "Post the plan" hides right away.
    @State private var postedTick = 0
    @State private var reveal: GroupOption?
    @State private var lockInTaps = 0
    @State private var removeTaps = 0

    init(sessionID: String, state: MessagesState) {
        self.sessionID = sessionID
        self.state = state
        _live = State(initialValue: LiveSession(sessionID: sessionID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let session = live.session {
                    HStack(alignment: .firstTextBaseline) {
                        Text(session.title)
                            .font(Theme.display(20))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        // Only the creator starts over from here; everyone
                        // else can start their own from the app drawer.
                        if live.isOwner {
                            Button("New vote") { state.showNewVote() }
                                .font(Theme.body(13, .semibold))
                                .foregroundStyle(Theme.accentText)
                        }
                    }
                    Text("\(live.members.count) in the group · \(GroupWording.line(session, nonVoterNames: live.waitingNames))")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)

                    if let winner = session.winner {
                        WinnerCard(option: winner,
                                   detail: session.meetTime.map { "Meet \(MeetTimes.phrase(for: $0))" } ?? winner.category)
                        HStack(spacing: 8) {
                            ActionTile(title: "Directions", systemImage: "location.north.line",
                                       tint: Theme.accentText, background: Theme.surface) {
                                if let url = directionsURL(winner) { state.open(url: url) }
                            }
                            ActionTile(title: "Call", systemImage: "phone",
                                       tint: Theme.accentText, background: Theme.surface) {
                                if let url = phoneURL(winner) { state.open(url: url) }
                            }
                            .disabled(phoneURL(winner) == nil)
                            ActionTile(title: "Website", systemImage: "safari",
                                       tint: Theme.accentText, background: Theme.surface) {
                                if let url = winner.place.websiteURL { state.open(url: url) }
                            }
                            .disabled(winner.place.websiteURL == nil)
                        }
                        if live.isOwner {
                            let _ = postedTick
                            if MessagesState.bubbleIsOutdated(session) {
                                // One bubble when you're ready, not one per tap.
                                Button {
                                    state.sendUpdate(session, tally: live.tally, memberCount: live.members.count)
                                    postedTick += 1
                                } label: {
                                    Label("Post the plan to the chat", systemImage: "paperplane.fill")
                                        .font(Theme.display(16))
                                        .foregroundStyle(Theme.onSaffron)
                                        .frame(maxWidth: .infinity, minHeight: 50)
                                        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            MessagePlanControls(session: session)
                        } else if let note = session.trimmedNote {
                            PlanNoteCard(note: note, author: session.createdByName)
                        }
                        if let meet = session.meetTime, meet.timeIntervalSinceNow > -15 * 60 {
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
                        if live.isOwner {
                            Button {
                                Task {
                                    do {
                                        try await GroupService.shared.reopen(session: session)
                                        LeaveBy.cancel(sessionID: session.id)
                                        // Replace the "We're going to X" bubble, so the chat
                                        // doesn't keep showing a plan that's open again.
                                        var reopened = session
                                        reopened.status = .open
                                        reopened.winnerID = nil
                                        reopened.closesAt = nil
                                        state.sendUpdate(reopened, tally: live.tally, memberCount: live.members.count)
                                    }
                                    catch { errorMessage = GroupService.message(for: error) }
                                }
                            } label: {
                                Label(session.mode == .vote ? "Reopen voting" : "Reopen picks", systemImage: "arrow.uturn.backward")
                                    .font(Theme.body(14, .semibold))
                                    .foregroundStyle(Theme.accentText)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        let tally = live.tally
                        let slots = max(live.members.count, tally.totalVotes, 1)
                        let ruledOut = live.ruledOutIDs
                        let _ = timeUpTick
                        let open = session.acceptsChanges
                        let leader = session.eligibleLeader(votes: live.votes, ruledOut: ruledOut)
                        if let closesAt = session.closesAt, session.mode == .vote {
                            VoteCountdown(closesAt: closesAt)
                        }
                        if live.isOwner && live.members.count <= 1 {
                            inviteCard(session)
                        }
                        if session.mode == .spin {
                            SpinProgressLine(waiting: live.waitingOnPicks, memberCount: live.members.count)
                        }
                        VoteNotices(session: session, isOwner: live.isOwner,
                                    everythingRuledOut: live.everythingRuledOut,
                                    myVoteIsRuledOut: live.myVote.map { ruledOut.contains($0) } ?? false)
                        ForEach(session.options) { option in
                            VoteOptionRow(option: option,
                                          votes: tally.count(for: option.id),
                                          totalSlots: slots,
                                          voters: tally.votersByOption[option.id] ?? [],
                                          isMine: live.myVote == option.id,
                                          isLeading: leader == option.id,
                                          isEnabled: !isWorking && session.mode == .vote && open
                                              && (!ruledOut.contains(option.id) || live.myVote == option.id),
                                          showsVotes: session.mode == .vote,
                                          isRuledOut: ruledOut.contains(option.id)) {
                                vote(option, session: session)
                            }
                        }
                        AddPlaceButton(session: session, userID: GroupService.shared.currentUserID) {
                            state.expand()
                            Task {
                                // Adding a place is taking part: join first.
                                do { try await GroupService.shared.joinIfNeeded(sessionID: session.id) }
                                catch { errorMessage = GroupService.message(for: error); return }
                                showAdd = true
                            }
                        }
                        if live.isOwner {
                            OwnerGroupTools(session: session,
                                            nudge: Nudge.text(session: session, members: live.members, votes: live.votes),
                                            sendNudge: { state.insertText($0) },
                                            onRemove: { removing = $0 })
                        }
                        if live.isOwner {
                            Button {
                                if GroupWording.lockInWarning(session, totalVotes: tally.totalVotes) != nil {
                                    confirmLockIn = true
                                } else {
                                    lockIn(session)
                                }
                            } label: {
                                Text(session.mode == .spin ? "Spin it" : "Lock it in")
                                    .font(Theme.display(17))
                                    .foregroundStyle(Theme.onSaffron)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking || session.options.isEmpty)
                        } else {
                            Text(GroupWording.whoDecides(session))
                                .font(Theme.body(14, .semibold))
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    // Only people who've joined (voted or added) have anything to leave.
                    if live.isOwner || live.members.contains(where: { $0.id == GroupService.shared.currentUserID }) {
                        Button(live.isOwner ? "End group for everyone" : "Leave group", role: .destructive) {
                            if live.isOwner { confirmEnd = true } else { confirmLeave = true }
                        }
                        .font(Theme.body(13, .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(Theme.body(13)).foregroundStyle(Theme.danger)
                    }
                } else if live.isGone {
                    Text("This group plan has ended.")
                        .font(Theme.body(15, .semibold))
                        .foregroundStyle(Theme.muted)
                    Button("Start a new vote") { state.showNewVote() }
                        .font(Theme.body(15, .bold))
                        .foregroundStyle(Theme.accentText)
                } else if let message = live.errorMessage {
                    Label(message, systemImage: "wifi.slash")
                        .font(Theme.body(14, .semibold))
                        .foregroundStyle(Theme.muted)
                } else {
                    GroupPlanSkeleton(compact: true)
                }
            }
            .padding(16)
        }
        // When it's decided while you watch (not on opening a decided plan, or on
        // reopening). A Group Spin's reveal plays its own when the wheel lands.
        .sensoryFeedback(Haptic.decided, trigger: live.session?.status) { old, new in
            old == .open && new == .decided && live.session?.mode != .spin
        }
        .sensoryFeedback(Haptic.commit, trigger: lockInTaps)
        .sensoryFeedback(Haptic.commit, trigger: postedTick)
        .sensoryFeedback(Haptic.destructive, trigger: removeTaps)
        // Watch only; you join when you vote or add a place.
        .task { await live.start() }
        // A timed vote locks itself in when time's up, if the creator has it open.
        .task(id: live.session?.closesAt) { await autoCloseWhenTimeIsUp() }
        .task(id: live.session?.closesAt) {
            guard let wait = live.session?.closesAt?.timeIntervalSinceNow, wait > 0 else { return }
            try? await Task.sleep(for: .seconds(wait + 0.5))
            if !Task.isCancelled { timeUpTick += 1 }
        }
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
        .confirmationDialog("End this group plan?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End for everyone", role: .destructive) { end() }
        } message: {
            Text("Votes and the join code are deleted, and everyone’s told it has ended.")
        }
        .confirmationDialog("Leave this group plan?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { leave() }
        } message: {
            Text("Your vote is removed. You can rejoin anytime by voting again.")
        }
        .confirmationDialog(lockInWarning.title, isPresented: $confirmLockIn, titleVisibility: .visible) {
            if let session = live.session {
                Button(session.mode == .vote ? "Lock it in anyway" : "Spin anyway") { lockIn(session) }
            }
        } message: {
            Text(lockInWarning.message)
        }
    }

    private var lockInWarning: (title: String, message: String) {
        // Never an empty title: a vote can land between the tap and the dialog
        // (or while it animates away), which clears the warning.
        guard let session = live.session else { return ("Lock it in?", "") }
        return GroupWording.lockInWarning(session, totalVotes: live.tally.totalVotes)
            ?? (session.mode == .vote ? "Lock it in now?" : "Spin now?", "")
    }

    /// While nobody else has joined: friends tap the bubble, or use the link.
    private func inviteCard(_ session: GroupSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Waiting for friends", systemImage: "person.badge.plus")
                .font(Theme.body(15, .bold))
                .foregroundStyle(Theme.text)
            Text("Friends with ForkRoad tap the bubble to join. Anyone without it can use the web link.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let url = GroupLinks.webURL(sessionID: session.id, host: AppConfig.webHost) {
                Button {
                    state.insertText("\(GroupWording.inviteText(session)) \(url.absoluteString)")
                } label: {
                    Label("Send the web link", systemImage: "link")
                        .font(Theme.body(14, .bold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(Theme.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .card(radius: 18)
    }

    private func end() {
        guard let session = live.session else { return }
        Task {
            do {
                live.stop()
                try await GroupService.shared.endSession(session)
                state.showNewVote()
            } catch {
                errorMessage = GroupService.message(for: error)
                await live.start()
            }
        }
    }

    private func leave() {
        Task {
            do {
                try await GroupService.shared.leaveSession(sessionID)
                state.showNewVote()
            } catch { errorMessage = GroupService.message(for: error) }
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
                // Voting is taking part: join first (once).
                try await GroupService.shared.joinIfNeeded(sessionID: session.id)
                if live.myVote == option.id {
                    try await GroupService.shared.removeVote(sessionID: session.id)
                } else {
                    try await GroupService.shared.vote(sessionID: session.id, optionID: option.id, displayName: name)
                }
                // The live tally updates here. We don't post a new bubble per
                // vote, so the group isn't notified for every tap; the bubble
                // updates once, when the result is locked in.
            } catch { errorMessage = GroupService.message(for: error) }
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
        removeTaps += 1
        Task {
            do { try await GroupService.shared.removeOption(option.id, from: session) }
            catch { errorMessage = GroupService.message(for: error) }
        }
    }

    private func lockIn(_ session: GroupSession) {
        lockInTaps += 1
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
            } catch { errorMessage = GroupService.message(for: error) }
        }
    }

    private func phoneURL(_ option: GroupOption) -> URL? {
        guard let phone = option.phoneNumber else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
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
                errorMessage = GroupService.message(for: error)
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
/// Posting to the chat is a separate button, so trying times doesn't spam it.
struct MessagePlanControls: View {
    let session: GroupSession
    /// Sends an updated bubble after the time changes.

    @State private var showPicker = false
    @State private var noteDraft = ""
    @State private var savingNote = false
    @State private var errorMessage: String?
    @FocusState private var noteFocused: Bool
    @State private var timeTaps = 0

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
            timeButton(isCustom ? "Custom: \(session.meetTime.map { MeetTimes.label(for: $0) } ?? "")" : "Pick another time…",
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
        .sensoryFeedback(Haptic.tick, trigger: timeTaps)
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
        timeTaps += 1
        errorMessage = nil
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
