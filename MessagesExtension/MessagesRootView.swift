import SwiftUI
import Messages
import PickerCore

/// Chooses what the extension shows: setup, name prompt, a vote, or "new vote".
struct MessagesRootView: View {
    @Bindable var state: MessagesState
    @State private var hasName = Identity.displayName != nil

    var body: some View {
        Group {
            if !state.isReady {
                // A split second while Firebase connects (after the first frame).
                ProgressView()
                    .tint(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !state.firebaseReady {
                notice("Open Tablewhere to finish setting up group voting.")
            } else if !hasName {
                if state.isExpanded {
                    NamePromptView { _ in hasName = true }
                } else {
                    startButton(title: "Set up Tablewhere voting") { state.expand() }
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
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
        .buttonStyle(.pressable)
        .padding(16)
    }
}

/// Start a group plan from the chat, the same way as the app: choose how to
/// decide (Vote, Spin our picks, Surprise us, I'll pick), a name, the places,
/// and optionally when.
struct NewVoteView: View {
    @Bindable var state: MessagesState

    @State private var selected: [Place] = []
    /// An area picked in the place picker; saved on the plan for everyone.
    @State private var pickedArea: PickerArea?
    @State private var includeWebLink = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var query = ""
    @AppStorage(Preferences.noFastFoodKey, store: SharedDefaults.store) private var excludeFastFood = true
    @AppStorage(Preferences.noCoffeeSweetsKey, store: SharedDefaults.store) private var excludeCoffeeAndSweets = true

    @State private var setup: SetupMode = .vote
    @State private var title = ""
    @State private var closesIn: Int? = nil
    @State private var sendTaps = 0
    // Surprise us (its own area, so switching modes doesn't mix them up)
    @State private var surpriseArea: PickerArea?
    @State private var surpriseFilters: PlacePickerFilters?
    @State private var wheel: [Place] = []
    @State private var isLoadingWheel = true
    /// Vote, spin, and Surprise us: an optional date and time.
    @State private var hasTime = false
    // "I'll pick" (and the optional time for the others)
    @State private var meetTime = PlanSetupRows.defaultMeetTime()
    @State private var note = ""
    @State private var asksRSVP = false
    @State private var hasReplyBy = false
    @State private var replyBy = PlanSetupRows.defaultReplyBy(for: PlanSetupRows.defaultMeetTime())

    // What the app shares with the extension, read once.
    @State private var searchArea = SharedCache.loadSearchArea()
    @State private var nearby = SharedCache.loadNearby()
    @State private var areaName: String?

    /// A vote starts with 2–8 of your places; a spin starts with your one
    /// pick; an "I'll pick" plan has its one place.
    private var maxOptions: Int { setup == .vote ? GroupMode.maxStartingVoteOptions : 1 }
    private var isSingle: Bool { setup != .vote }

    private var rules: Randomizer.Rules {
        var rules = SharedCache.pickRules()
        rules.excludeFastFood = excludeFastFood
        rules.excludeCoffeeAndSweets = excludeCoffeeAndSweets
        return rules
    }

    private var startingFilters: PlacePickerFilters {
        searchArea.map { PlacePickerFilters($0) } ?? PlacePickerFilters()
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
                        Text("Start a group plan").font(Theme.display(18))
                        Text("Vote, spin, or let the wheel surprise you").font(Theme.body(12, .medium))
                    }
                    Spacer()
                }
                .foregroundStyle(Theme.onSaffron)
                .padding(14)
                .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.pressable)
            .padding(16)
        } else {
            List {
                modeSection
                Section {
                    TextField(setup.defaultTitle, text: $title)
                        .foregroundStyle(Theme.text)
                        .submitLabel(.done)
                } header: {
                    Text("Name")
                }
                .listRowBackground(Theme.surface)

                switch setup {
                case .surprise:
                    SurpriseWheelSection(
                        center: searchArea?.center,
                        centerName: areaName ?? "Your last search area",
                        startingFilters: startingFilters,
                        startingNearby: nearby,
                        rules: rules,
                        search: MapKitPlaceSearch(),
                        area: $surpriseArea,
                        filters: Binding(get: { surpriseFilters ?? startingFilters },
                                         set: { surpriseFilters = $0 }),
                        wheel: $wheel,
                        isLoading: $isLoadingWheel
                    )
                case .vote, .spin, .plan:
                    placesSections
                    if setup == .plan {
                        PlanSetupRows(meetTime: $meetTime, note: $note, asksRSVP: $asksRSVP,
                                      hasReplyBy: $hasReplyBy, replyBy: $replyBy)
                    }
                }
                if setup != .plan { PlanWhenSection(hasTime: $hasTime, meetTime: $meetTime) }

                Section {
                    Toggle("Also send a web link for friends without Tablewhere", isOn: $includeWebLink)
                        .tint(Theme.saffron)
                }
                .listRowBackground(Theme.surface)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger).listRowBackground(Color.clear)
                }
            }
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .sensoryFeedback(Haptic.tick, trigger: setup)
            .onChange(of: setup) {
                if isSingle && selected.count > 1 { selected = Array(selected.prefix(1)) }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .task {
                guard let center = searchArea?.center, areaName == nil else { return }
                areaName = await PickerArea.cityName(for: center)
            }
        }
    }

    // MARK: Sections

    private var modeSection: some View {
        Section {
            ForEach(SetupMode.allCases) { option in
                Button {
                    withAnimation(.snappy) { setup = option }
                } label: {
                    SetupModeRow(option: option, isOn: setup == option)
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(setup == option ? .isSelected : [])
            }
            if setup == .vote {
                Picker("Voting closes", selection: $closesIn) {
                    Text("When I lock it in").tag(Int?.none)
                    Text("In 5 min").tag(Int?.some(5))
                    Text("In 15 min").tag(Int?.some(15))
                    Text("In 30 min").tag(Int?.some(30))
                }
                .tint(Theme.accentText)
            }
        } header: {
            Text("How do you want to decide?")
        }
        .listRowBackground(Theme.surface)
    }

    /// Search, what you've picked, and the picker (the drawer has no nav bar
    /// for `.searchable`, so the search field is a row).
    @ViewBuilder private var placesSections: some View {
        Section {
            ForEach(selected) { place in
                HStack(spacing: 12) {
                    MonogramTile(name: place.name, category: place.category, size: 30)
                    Text(place.name).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    Button { toggle(place) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Remove \(place.name)")
                }
            }
            MessageSearchField(text: $query)
        } header: {
            Text(placesHeader)
        } footer: {
            if setup == .vote {
                Text("Start with 2–\(GroupMode.maxStartingVoteOptions). Friends can suggest one each, up to \(GroupSession.maxOptions) in all.")
            } else if setup == .spin {
                Text("Friends add theirs from the bubble or the link. You spin when everyone’s in.")
            }
        }
        .listRowBackground(Theme.surface)
        MessagePlacePicker(query: query, excludeFastFood: excludeFastFood,
                           accessory: { .check(isOn: selected.contains($0)) },
                           isDisabled: { setup == .vote && !selected.contains($0) && selected.count >= maxOptions },
                           onAreaChange: { pickedArea = $0 },
                           onTap: toggle)
    }

    private var placesHeader: String {
        switch setup {
        case .vote: return selected.isEmpty ? "Places" : "Places (\(selected.count) of \(maxOptions))"
        case .spin: return "Your pick"
        default: return "The place"
        }
    }

    // MARK: Send

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Text(statusLine)
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Button(action: send) {
                HStack(spacing: 8) {
                    if isSending { ProgressView().tint(Theme.onSaffron) }
                    Text(setup.startTitle)
                }
                .font(Theme.display(17))
                .foregroundStyle(canSend ? Theme.onSaffron : Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(canSend ? Theme.saffron : Theme.surfaceHigh,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.pressable)
            .disabled(!canSend || isSending)
            .sensoryFeedback(Haptic.commit, trigger: sendTaps)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.night)
        .animation(.snappy, value: canSend)
    }

    private var statusLine: String {
        if setup != .plan && hasTime && meetTime.timeIntervalSinceNow <= 0 { return "Pick a time that hasn’t passed" }
        switch setup {
        case .vote:
            if selected.count < 2 { return "Add at least 2 places" }
            return "\(selected.count) places to vote on"
        case .spin:
            return selected.first.map { "Your pick: \($0.name)" } ?? "Choose your pick to start"
        case .surprise:
            if isLoadingWheel && wheel.isEmpty { return "Finding places nearby…" }
            if wheel.count < 2 { return "Need 2+ places nearby. Try a bigger radius." }
            return "\(wheel.count) places on the wheel"
        case .plan:
            guard let place = selected.first else { return "Choose the place to send the plan" }
            if meetTime.timeIntervalSinceNow <= 0 { return "Pick a time that hasn’t passed" }
            return "\(place.name) · \(MeetTimes.label(for: meetTime))"
        }
    }

    private var canSend: Bool {
        if setup != .plan && hasTime && meetTime.timeIntervalSinceNow <= 0 { return false }
        switch setup {
        case .vote: return selected.count >= 2
        case .spin: return selected.count >= 1
        case .surprise: return wheel.count >= 2 && !isLoadingWheel
        case .plan: return selected.count == 1 && meetTime.timeIntervalSinceNow > 0
        }
    }

    /// What you typed, or the default name.
    private var groupTitle: String {
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return String(typed.prefix(60)) }
        return setup.defaultTitle
    }

    private func toggle(_ place: Place) {
        if let i = selected.firstIndex(of: place) { selected.remove(at: i) }
        else if isSingle { selected = [place] }  // one pick: tapping another swaps it
        else if selected.count < maxOptions { selected.append(place) }
    }

    /// Where everyone else's picker starts: the area picked here, else the
    /// app's last search area (named, since the extension doesn't know it).
    private func groupArea(creatorName: String) async -> GroupArea? {
        if let chosen = setup == .surprise ? surpriseArea : pickedArea { return chosen.groupArea }
        guard let center = searchArea?.center else { return nil }
        let name: String
        if let areaName { name = areaName }
        else { name = await PickerArea.cityName(for: center) ?? "\(creatorName)’s area" }
        return GroupArea(name: name, latitude: center.latitude, longitude: center.longitude)
    }

    private func send() {
        guard let name = Identity.displayName, canSend else { return }
        sendTaps += 1
        isSending = true
        errorMessage = nil
        let setup = self.setup
        let isPlan = setup == .plan
        let places = setup == .surprise ? wheel : selected
        Task {
            defer { isSending = false }
            do {
                let session = try await GroupService.shared.createSession(
                    title: groupTitle,
                    mode: setup.groupMode,
                    // Surprise us: the rows say "added by the wheel", not you.
                    options: places.map { GroupOption(place: $0, addedBy: setup == .surprise ? "the wheel" : name) },
                    closesInMinutes: setup == .vote ? closesIn : nil,
                    displayName: name,
                    area: await groupArea(creatorName: name),
                    meetTime: isPlan || hasTime ? meetTime : nil,
                    note: isPlan ? note : nil,
                    asksRSVP: isPlan && asksRSVP,
                    rsvpBy: isPlan && asksRSVP && hasReplyBy ? PlanSetupRows.clampedReplyBy(replyBy, meetTime: meetTime) : nil,
                    surprise: setup == .surprise
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
    /// The plan's status as of the last change seen (nil until it loads).
    @State private var lastStatus: GroupStatus?
    @State private var lockInTaps = 0
    @State private var rsvpTaps = 0
    @State private var removeTaps = 0

    init(sessionID: String, state: MessagesState) {
        self.sessionID = sessionID
        self.state = state
        _live = State(initialValue: LiveSession(sessionID: sessionID))
    }

    var body: some View {
        withDialogs(withEffects(content))
    }

    /// The plan's status as this person may see it: a result the creator is
    /// holding (spin reveal, or iMessage before Send) still looks open to
    /// everyone else until it's shared.
    private var visiblePhase: GroupStatus? {
        guard let session = live.session else { return nil }
        if session.status == .decided && session.announced == false && !live.isOwner { return .open }
        return session.status
    }

    /// The plan as this view shows it. While a Group Spin's reveal plays (and
    /// in the moment before it starts), it still looks open, so the winner
    /// behind the wheel doesn't give the answer away.
    private var shownSession: GroupSession? {
        guard var session = live.session else { return nil }
        let justDecided = lastStatus == .open || reveal != nil
        let held = session.status == .decided && session.announced == false && !live.isOwner
        if held || (session.mode == .spin && session.status == .decided && justDecided) {
            session.status = .open
            session.winnerID = nil
        }
        return session
    }

    // Split up so the compiler can type-check it in reasonable time.
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let session = shownSession {
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
                    if session.winner == nil, let meet = session.meetTime {
                        Label(MeetTimes.label(for: meet), systemImage: "calendar")
                            .font(Theme.body(14, .semibold))
                            .foregroundStyle(Theme.accentText)
                    }

                    if let winner = session.winner {
                        decidedSection(session, winner: winner)
                    } else {
                        openSection(session)
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
                    Button("Start a new plan") { state.showNewVote() }
                        .font(Theme.body(15, .bold))
                        .foregroundStyle(Theme.accentText)
                } else if let message = live.errorMessage {
                    Label(message, systemImage: "wifi.slash")
                        .font(Theme.body(14, .semibold))
                        .foregroundStyle(Theme.muted)
                    Button("Try again") { Task { await live.retry() } }
                        .font(Theme.body(15, .bold))
                        .foregroundStyle(Theme.accentText)
                } else {
                    GroupPlanSkeleton(compact: true)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func decidedSection(_ session: GroupSession, winner: GroupOption) -> some View {
        WinnerCard(option: winner,
                   detail: session.meetTime.map { "Meet \(MeetTimes.phrase(for: $0))" } ?? winner.category,
                   eyebrow: session.mode == .plan ? "THE PLAN" : session.mode == .spin ? "THE WHEEL PICKED" : "THE GROUP PICKED")
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
            // Time and note first, then one bubble with all of it.
            MessagePlanControls(session: session)
            // Held results always offer Send (even if a matching bubble was posted before).
            if MessagesState.bubbleIsOutdated(session) || session.announced == false {
                if session.announced == false {
                    Text("Only you can see this so far. Add a time or note if you like, then send it.")
                        .font(Theme.body(13, .medium))
                        .foregroundStyle(Theme.muted)
                }
                // One bubble when you're ready, not one per tap.
                Button {
                    state.sendUpdate(session, tally: live.tally, memberCount: live.members.count)
                    postedTick += 1
                    if session.announced == false {
                        Task {
                            do { try await GroupService.shared.announce(sessionID: session.id) }
                            catch { errorMessage = "Sent to the chat, but the app couldn’t tell everyone else. Tap Send again." }
                        }
                    }
                } label: {
                    Label(session.announced == false ? "Send to the group" : "Post the updated plan",
                          systemImage: "paperplane.fill")
                        .font(Theme.display(16))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
            }
        } else if let note = session.trimmedNote {
            PlanNoteCard(note: note, author: session.createdByName)
        }
        if let meet = session.meetTime, meet.timeIntervalSinceNow > -15 * 60 {
            AddToCalendarButton(session: session, winner: winner, meetTime: meet)
            LeaveByCard(sessionID: session.id, winner: winner, meetTime: meet,
                        origin: { await MessageLeaveOrigin.current() },
                        askForLocation: { await OneShotLocation.shared.requestPermission() })
        }
        if session.hasRSVP {
            RSVPPanel(session: session, count: live.rsvpCount, mine: live.myRSVP,
                      isOwner: live.isOwner, isWorking: isWorking, noReply: live.noRSVPYet) { going, guests in
                answer(going: going, guests: guests, session: session)
            }
        }
        if session.mode == .vote {
            VoteBreakdown(options: session.options,
                          tally: live.tally,
                          winnerID: session.winnerID,
                          nonVoters: live.nonVoterNames)
        }
        // A plan was never open, so there's nothing to reopen.
        if live.isOwner && session.mode != .plan {
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
            .buttonStyle(.pressable)
        }
    }

    @ViewBuilder
    private func openSection(_ session: GroupSession) -> some View {
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
        if session.mode == .spin && !session.isSurprise {
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
                          isLeading: session.mode == .vote && leader == option.id,
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
            .buttonStyle(.pressable)
            .disabled(isWorking || session.options.isEmpty)
        } else {
            Text(GroupWording.whoDecides(session))
                .font(Theme.body(14, .semibold))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func withEffects<V: View>(_ view: V) -> some View {
        view
        // When it's decided while you watch (not on opening a decided plan, or on
        // reopening). A Group Spin's reveal plays its own when the wheel lands.
        .sensoryFeedback(Haptic.decided, trigger: visiblePhase) { old, new in
            old == .open && new == .decided && live.session?.mode != .spin
        }
        .sensoryFeedback(Haptic.commit, trigger: lockInTaps)
        .sensoryFeedback(Haptic.commit, trigger: postedTick)
        .sensoryFeedback(Haptic.destructive, trigger: removeTaps)
        .sensoryFeedback(Haptic.commit, trigger: rsvpTaps)
        // Watch only; you join when you vote or add a place.
        .task { await live.start() }
        // A timed vote locks itself in when time's up, if the creator has it open.
        .task(id: live.session?.closesAt) { await autoCloseWhenTimeIsUp() }
        .task(id: live.session?.closesAt) {
            guard let wait = live.session?.closesAt?.timeIntervalSinceNow, wait > 0 else { return }
            try? await Task.sleep(for: .seconds(wait + 0.5))
            if !Task.isCancelled { timeUpTick += 1 }
        }
        .onChange(of: visiblePhase) { old, new in
            defer { lastStatus = new }
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
    }

    private var removingBinding: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private func withDialogs<V: View>(_ view: V) -> some View {
        view
        .confirmationDialog("Remove \(removing?.name ?? "this place")?",
                            isPresented: removingBinding,
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
            Text("Friends with Tablewhere tap the bubble to join. Anyone without it can use the web link.")
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
                .buttonStyle(.pressable)
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

    private func answer(going: Bool, guests: Int, session: GroupSession) {
        guard let name = Identity.displayName else {
            errorMessage = "Open Tablewhere and add your name to reply."
            return
        }
        if !state.isExpanded { state.expand() }
        rsvpTaps += 1
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await GroupService.shared.rsvp(sessionID: session.id, going: going, guests: guests, displayName: name)
            } catch {
                errorMessage = GroupService.message(for: error)
            }
        }
    }

    private func vote(_ option: GroupOption, session: GroupSession) {
        guard let name = Identity.displayName else {
            errorMessage = "Open Tablewhere and add your name to vote."
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
        // Like Lock in: the creator is here, and sends it with the time and note.
        _ = try? await GroupService.shared.decide(session: current, votes: live.votes, ruledOut: live.ruledOutIDs,
                                                  announce: false)
        state.expand()
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
                // The result shows here first (with the spin's reveal); the
                // chat hears it when you tap Send to the group, with the time
                // and note in the same bubble. The push waits for that too.
                _ = try await GroupService.shared.decide(session: session, votes: live.votes,
                                                         ruledOut: live.ruledOutIDs, announce: false)
                state.expand()
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
    @AppStorage(Preferences.noFastFoodKey, store: SharedDefaults.store) private var excludeFastFood = true

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
                                   groupArea: session.area,
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
            } catch {
                errorMessage = GroupService.message(for: error)
            }
        }
    }
}

/// The group place picker fed from what the app shares with the extension:
/// saved lists, the last nearby results, and where the app last searched.
struct MessagePlacePicker: View {
    let query: String
    let excludeFastFood: Bool
    /// Read live, so flipping the chip in the picker updates the list.
    @AppStorage(Preferences.noCoffeeSweetsKey, store: SharedDefaults.store) private var excludeCoffeeAndSweets = true
    var excludedIDs: Set<String> = []
    var groupBlockedHashes: Set<String> = []
    var sessionID: String?
    /// The group's area (set by its creator): start there instead of the
    /// app's last search area.
    var groupArea: GroupArea?
    let accessory: (Place) -> PlacePickerAccessory
    var isDisabled: (Place) -> Bool = { _ in false }
    var onAreaChange: (PickerArea?) -> Void = { _ in }
    let onTap: (Place) -> Void

    // Read once per sheet, not on every redraw.
    @State private var area = SharedCache.loadSearchArea()
    @State private var favorites = SharedCache.loadFavorites()
    @State private var interested = SharedCache.loadInterested()
    @State private var nearby = SharedCache.loadNearby()

    private var rules: Randomizer.Rules {
        var rules = SharedCache.pickRules()
        rules.excludeFastFood = excludeFastFood
        rules.excludeCoffeeAndSweets = excludeCoffeeAndSweets
        return rules
    }

    var body: some View {
        GroupPlacePicker(
            query: query,
            center: groupArea?.coordinate ?? area?.center,
            centerName: groupArea.map { "Group area: \($0.name)" } ?? "Last search area",
            favorites: favorites,
            interested: interested,
            startingFilters: area.map { PlacePickerFilters($0) } ?? PlacePickerFilters(),
            // The app's last results only fit when there's no group area.
            startingNearby: groupArea == nil ? nearby : [],
            rules: rules,
            excludedIDs: excludedIDs,
            groupBlockedHashes: groupBlockedHashes,
            sessionID: sessionID,
            accessory: accessory,
            isDisabled: isDisabled,
            onAreaChange: onAreaChange,
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
                .buttonStyle(.pressable)
                .accessibilityLabel("Clear search")
            }
        }
    }
}

/// The iMessage extension's "No fast food" chip (the app's reads AppModel).
/// Same saved setting, so the app and extension stay in sync.
struct NoFastFoodChip: View {
    @AppStorage(Preferences.noFastFoodKey, store: SharedDefaults.store) private var excludeFastFood = true

    var body: some View {
        FastFoodChip(isOn: $excludeFastFood)
    }
}

/// The iMessage extension's "Filters" chip (same saved settings as the app).
struct PlaceFiltersChip: View {
    @AppStorage(Preferences.noFastFoodKey, store: SharedDefaults.store) private var noFastFood = true
    @AppStorage(Preferences.noCoffeeSweetsKey, store: SharedDefaults.store) private var noCoffee = true

    var body: some View {
        FoodFiltersChip(noFastFood: $noFastFood, noCoffeeSweets: $noCoffee)
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
            if session.mode == .plan {
                // A plan can be days out: any date and time.
                timeButton(session.meetTime.map { "\(MeetTimes.label(for: $0)) · Change" } ?? "Set a time",
                           isOn: false) { showPicker = true }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(slots, id: \.self) { slot in
                        timeButton(slot.formatted(date: .omitted, time: .shortened), isOn: isSlot(slot)) { setTime(slot) }
                    }
                }
                timeButton(isCustom ? "Custom: \(session.meetTime.map { MeetTimes.label(for: $0) } ?? "")" : "Pick another time…",
                           isOn: isCustom) { showPicker = true }
            }

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
                        .buttonStyle(.pressable)
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
            if session.mode == .plan {
                PlanTimeSheet(initial: session.meetTime ?? PlanSetupRows.defaultMeetTime()) { setTime($0) }
            } else {
                PlanTimeSheet(initial: session.meetTime ?? slots.first ?? .now) { setTime($0) }
            }
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
        .buttonStyle(.pressable)
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
