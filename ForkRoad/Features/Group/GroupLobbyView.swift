import SwiftUI
import CoreLocation
import SwiftData
import PickerCore

/// A live group plan: invite, vote (or add places for a spin), lock it in,
/// then set a meeting time and send everyone the plan.
struct GroupLobbyView: View {
    let sessionID: String

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var confirmEnd = false
    @State private var confirmLeave = false
    @State private var live: LiveSession
    @State private var showAddPlace = false
    @State private var browserURL: URL?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var showTimePicker = false
    @State private var noteDraft = ""
    @State private var removing: GroupOption?
    /// Bumped when a vote's timer runs out, so the screen switches to "closed".
    @State private var timeUpTick = 0
    @State private var reveal: GroupOption?
    /// The plan's status as of the last change seen (nil until it loads).
    @State private var lastStatus: GroupStatus?
    @State private var confirmLockIn = false
    @State private var showNamePrompt = false
    @State private var pendingVote: GroupOption?
    @FocusState private var noteFocused: Bool
    /// Bumped by taps that play a haptic but change nothing observable here.
    @State private var commitTaps = 0
    @State private var removeTaps = 0
    @State private var timeTaps = 0

    init(sessionID: String) {
        self.sessionID = sessionID
        _live = State(initialValue: LiveSession(sessionID: sessionID))
    }

    var body: some View {
        withEffects(withDialogs(withChrome(content)))
    }

    /// The plan as this screen shows it. While a Group Spin's reveal plays (and
    /// in the moment before it starts), it still looks open, so the winner card
    /// behind the wheel doesn't give the answer away.
    private var shownSession: GroupSession? {
        guard var session = live.session else { return nil }
        let justDecided = lastStatus == .open || reveal != nil
        if session.mode == .spin && session.status == .decided && justDecided {
            session.status = .open
            session.winnerID = nil
        }
        return session
    }

    // Split up so the compiler can type-check it in reasonable time.
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let session = shownSession {
                    header(session)
                    if session.status == .decided, let winner = session.winner {
                        decided(session, winner: winner)
                    } else {
                        deciding(session)
                    }
                } else if live.isGone {
                    StateCard(icon: "flag.checkered",
                              title: "This group plan has ended",
                              message: "The person who started it ended it, or it no longer exists.",
                              action: ("Back to Group", { SharedCache.forgetSession(sessionID); dismiss() }))
                        .padding(.top, 40)
                } else if let message = live.errorMessage {
                    StateCard(icon: "wifi.slash", title: "Can’t reach this group", message: message)
                        .padding(.top, 40)
                } else {
                    GroupPlanSkeleton()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
    }

    private func withChrome<V: View>(_ view: V) -> some View {
        view
        .background(Theme.night)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let session = shownSession {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if live.isOwner {
                            Button("End group for everyone", systemImage: "xmark.circle", role: .destructive) {
                                confirmEnd = true
                            }
                        } else {
                            Button("Leave group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                confirmLeave = true
                            }
                        }
                        if session.status == .decided && live.isOwner {
                            Button("Reopen voting", systemImage: "arrow.uturn.backward") { reopen(session) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Group options")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var removingBinding: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private func withDialogs<V: View>(_ view: V) -> some View {
        view
        .confirmationDialog("End this group plan?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End for everyone", role: .destructive) { endGroup() }
        } message: {
            Text("Votes and the join code are deleted, and everyone’s told it has ended.")
        }
        .confirmationDialog("Leave this group plan?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { leaveGroup() }
        } message: {
            Text("Your vote is removed. You can rejoin with the code.")
        }
        .confirmationDialog(lockInWarning.title, isPresented: $confirmLockIn, titleVisibility: .visible) {
            if let session = live.session {
                Button(session.mode == .vote ? "Lock it in anyway" : "Spin anyway") { lockIn(session) }
            }
        } message: {
            Text(lockInWarning.message)
        }
        .sheet(isPresented: $showNamePrompt, onDismiss: namePromptDismissed) {
            NamePromptView { _ in showNamePrompt = false }
                .presentationDetents([.height(300)])
                .presentationBackground(Theme.night)
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showAddPlace) {
            if let session = live.session { AddOptionView(session: session, groupBlockedHashes: live.groupBlockedHashes) }
        }
        .sheet(item: $browserURL) { SafariView(url: $0).ignoresSafeArea() }
        .confirmationDialog("Remove \(removing?.name ?? "this place")?",
                            isPresented: removingBinding,
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) { removePlace() }
        } message: {
            Text("Its votes are cleared, and whoever added it can add a different place.")
        }
    }

    private func namePromptDismissed() {
        if let option = pendingVote, let session = live.session, Identity.displayName != nil {
            Task {
                try? await GroupService.shared.join(sessionID: session.id, displayName: Identity.displayName ?? "")
                vote(for: option, in: session)
            }
        }
        pendingVote = nil
    }

    private func withEffects<V: View>(_ view: V) -> some View {
        view
        .task {
            await live.start()
            // Your blacklist may have changed since you joined.
            await GroupService.shared.shareBlacklist(sessionID: sessionID)
        }
        .task(id: live.session?.closesAt) { await autoCloseWhenTimeIsUp() }
        .task(id: live.session?.closesAt) {
            guard let wait = live.session?.closesAt?.timeIntervalSinceNow, wait > 0 else { return }
            try? await Task.sleep(for: .seconds(wait + 0.5))
            if !Task.isCancelled { timeUpTick += 1 }
        }
        // When it's decided while you watch (not on opening a decided plan, or on
        // reopening). A Group Spin's reveal plays its own when the wheel lands.
        .sensoryFeedback(Haptic.decided, trigger: live.session?.status) { old, new in
            old == .open && new == .decided && live.session?.mode != .spin
        }
        .sensoryFeedback(Haptic.commit, trigger: commitTaps)
        .sensoryFeedback(Haptic.destructive, trigger: removeTaps)
        .sensoryFeedback(Haptic.tick, trigger: timeTaps)
        // Everyone watching a Group Spin sees the wheel land.
        .onChange(of: live.session?.status) { old, new in
            if old == .open, new == .decided, let session = live.session, session.mode == .spin,
               let winner = session.winner {
                reveal = winner
            }
            lastStatus = new
        }
        .overlay {
            if let reveal, let session = live.session {
                SpinReveal(names: session.options.map(\.name), winner: reveal.name) { self.reveal = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: reveal?.id)
    }

    // MARK: Header

    private func header(_ session: GroupSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: session.status == .decided ? "Decided" : (session.mode == .vote ? "Live vote" : "Group spin"))
                    Text(session.title)
                        .font(Theme.display(32))
                        .foregroundStyle(Theme.text)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("CODE").font(Theme.body(10, .bold)).foregroundStyle(Theme.muted)
                    Text(JoinCode.display(session.joinCode))
                        .font(Theme.code(17))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(Theme.muted.opacity(0.5)))
            }

            HStack(spacing: 12) {
                memberAvatars
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(live.members.count) in the group")
                        .font(Theme.body(15, .semibold))
                        .foregroundStyle(Theme.text)
                    Text(statusLine(session))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if let url = GroupLinks.webURL(sessionID: session.id, host: AppConfig.webHost) {
                    ShareLink(item: url,
                              subject: Text(session.title),
                              message: Text(GroupWording.inviteText(session))) {
                        Image(systemName: "square.and.arrow.up")
                            .font(Theme.body(17, .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 44, height: 44)
                            .background(Theme.surfaceHigh, in: Circle())
                    }
                    .accessibilityLabel("Invite friends")
                }
            }
            .padding(14)
            .card()
        }
        .padding(.top, 8)
    }

    private var memberAvatars: some View {
        HStack(spacing: -10) {
            ForEach(live.members.prefix(4)) { member in
                let colors = Theme.tileColors(for: member.name)
                Text(initials(member.name))
                    .font(Theme.body(13, .bold))
                    .foregroundStyle(colors.ink)
                    .frame(width: 38, height: 38)
                    .background(colors.background, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 3))
            }
        }
        .accessibilityHidden(true)
    }

    private func statusLine(_ session: GroupSession) -> String {
        GroupWording.line(session, nonVoterNames: live.waitingNames)
    }

    // MARK: Deciding

    @ViewBuilder
    private func deciding(_ session: GroupSession) -> some View {
        if let closesAt = session.closesAt, session.mode == .vote {
            VoteCountdown(closesAt: closesAt)
        }

        if live.isOwner && live.members.count <= 1 {
            inviteCard(session)
        }

        let tally = live.tally
        let slots = max(live.members.count, tally.totalVotes, 1)
        let ruledOut = live.ruledOutIDs
        let _ = timeUpTick
        let open = session.acceptsChanges
        let leader = session.eligibleLeader(votes: live.votes, ruledOut: ruledOut)
        if session.mode == .spin {
            SpinProgressLine(waiting: live.waitingOnPicks, memberCount: live.members.count)
        }
        VoteNotices(session: session, isOwner: live.isOwner,
                    everythingRuledOut: live.everythingRuledOut,
                    myVoteIsRuledOut: live.myVote.map { ruledOut.contains($0) } ?? false)
        if open { Label(session.mode == .vote
              ? (live.myVote == nil ? "Tap a place to cast your vote" : "Tap another place to change your vote")
              : "Everyone adds places, then \(live.isOwner ? "you spin" : "\(session.createdByName) spins")",
              systemImage: session.mode == .vote ? "hand.tap" : "sparkles")
            .font(Theme.body(14, .semibold))
            .foregroundStyle(Theme.accentText) }
        VStack(spacing: 10) {
            ForEach(session.options) { option in
                VoteOptionRow(
                    option: option,
                    votes: session.mode == .vote ? tally.count(for: option.id) : 0,
                    totalSlots: slots,
                    voters: session.mode == .vote ? (tally.votersByOption[option.id] ?? []) : [],
                    isMine: live.myVote == option.id,
                    isLeading: session.mode == .vote && leader == option.id,
                    // Your own vote stays tappable so you can take it back.
                    isEnabled: session.mode == .vote && open && !isWorking
                        && (!ruledOut.contains(option.id) || live.myVote == option.id),
                    showsVotes: session.mode == .vote,
                    isRuledOut: ruledOut.contains(option.id)
                ) {
                    vote(for: option, in: session)
                }
            }
        }

        AddPlaceButton(session: session, userID: GroupService.shared.currentUserID) { showAddPlace = true }

        if live.isOwner {
            OwnerGroupTools(session: session,
                            nudge: Nudge.text(session: session, members: live.members, votes: live.votes),
                            onRemove: { removing = $0 })
        }

        if session.mode == .vote {
            Label("If it ends in a tie, the app picks fairly between the tied places.", systemImage: "shuffle")
                .font(Theme.body(13))
                .foregroundStyle(Theme.muted)
        }
    }

    /// While it's just you: the next step is getting friends in.
    private func inviteCard(_ session: GroupSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("It’s just you so far", systemImage: "person.badge.plus")
                .font(Theme.body(16, .bold))
                .foregroundStyle(Theme.text)
            Text("Send the link to the group chat. Friends can \(session.mode == .vote ? "vote" : "add their pick") from the web, no app needed, or join in ForkRoad with code \(JoinCode.display(session.joinCode)).")
                .font(Theme.body(14))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let url = GroupLinks.webURL(sessionID: session.id, host: AppConfig.webHost) {
                ShareLink(item: url,
                          subject: Text(session.title),
                          message: Text(GroupWording.inviteText(session))) {
                    Label("Invite friends", systemImage: "square.and.arrow.up")
                        .font(Theme.display(16))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(16)
        .card(radius: 22)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.saffron.opacity(0.35)))
    }

    private var lockInWarning: (title: String, message: String) {
        // Never an empty title: a vote can land between the tap and the dialog
        // (or while it animates away), which clears the warning.
        guard let session = live.session else { return ("Lock it in?", "") }
        return GroupWording.lockInWarning(session, totalVotes: live.tally.totalVotes)
            ?? (session.mode == .vote ? "Lock it in now?" : "Spin now?", "")
    }

    // MARK: Decided

    @ViewBuilder
    private func decided(_ session: GroupSession, winner: GroupOption) -> some View {
        let count = live.tally.count(for: winner.id)
        // The meet day leads when there is one ("Meet tomorrow at 7:00 PM").
        let how = session.mode == .vote ? "\(count) of \(live.tally.totalVotes) votes" : "Picked by the spin"
        WinnerCard(option: winner,
                   detail: session.meetTime.map { "Meet \(MeetTimes.phrase(for: $0)) · \(how)" } ?? "\(how) · \(winner.category)")

        HStack(spacing: 8) {
            ActionTile(title: "Directions", systemImage: "location.north.line", tint: Theme.accentText, background: Theme.surface) {
                PlaceLinks.openDirections(winner.place)
                VisitFollowUp.record(winner.place, in: context)
            }
            ActionTile(title: "Call", systemImage: "phone", tint: Theme.accentText, background: Theme.surface) {
                if let url = PlaceLinks.phoneURL(winner.place) { openURL(url) }
            }
            .disabled(winner.phoneNumber == nil)
            ActionTile(title: "Website", systemImage: "safari", tint: Theme.accentText, background: Theme.surface) {
                browserURL = winner.place.websiteURL
            }
            .disabled(winner.websiteURL == nil)
        }

        meetTimeSection(session)
        if let meet = session.meetTime, meet.timeIntervalSinceNow > -15 * 60 {
            AddToCalendarButton(session: session, winner: winner, meetTime: meet)
            LeaveByCard(sessionID: session.id, winner: winner, meetTime: meet, title: session.title) {
                // Get a fresh GPS fix if location is on (it's only used on this phone).
                if model.location.authorization == .authorizedWhenInUse || model.location.authorization == .authorizedAlways {
                    model.location.start()
                }
                return LeaveBy.origin(model)
            }
        }
        noteSection(session)

        if session.mode == .vote {
            VoteBreakdown(options: session.options,
                          tally: live.tally,
                          winnerID: session.winnerID,
                          nonVoters: live.nonVoterNames)
        }
    }

    @ViewBuilder
    private func meetTimeSection(_ session: GroupSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: live.isOwner ? "Meet at" : "Meeting time")
            if live.isOwner {
                let slots = MeetTimes.slots()
                let isSlot: (Date) -> Bool = { slot in
                    session.meetTime.map { abs($0.timeIntervalSince(slot)) < 60 } ?? false
                }
                let isCustom = session.meetTime != nil && !slots.contains(where: isSlot)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(slots, id: \.self) { slot in
                        meetButton(slot.formatted(date: .omitted, time: .shortened), isOn: isSlot(slot)) {
                            setMeetTime(slot)
                        }
                    }
                    meetButton(isCustom ? (session.meetTime.map { MeetTimes.label(for: $0) } ?? "Custom")
                                        : "Custom…",
                               systemImage: "clock", isOn: isCustom) {
                        showTimePicker = true
                    }
                }
                .sheet(isPresented: $showTimePicker) {
                    MeetTimePickerSheet(initial: session.meetTime ?? slots.first ?? .now) { setMeetTime($0) }
                }
            } else {
                Text(session.meetTime.map { MeetTimes.label(for: $0) } ?? "\(session.createdByName) hasn’t set a time yet")
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.text)
            }
        }
    }

    private func meetButton(_ title: String, systemImage: String? = nil, isOn: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(Theme.body(14, .bold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(isOn ? Theme.night : Theme.text)
            .background(isOn ? Theme.text : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private func noteSection(_ session: GroupSession) -> some View {
        if live.isOwner {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Note for the group")
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Optional, like “Bring a gift!”", text: $noteDraft, axis: .vertical)
                        .lineLimit(1...3)
                        .font(Theme.body(15, .medium))
                        .foregroundStyle(Theme.text)
                        .focused($noteFocused)
                        .submitLabel(.done)
                        .onSubmit { saveNote() }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if noteIsDirty(session) {
                        Button("Save") { saveNote() }
                            .font(Theme.body(14, .bold))
                            .foregroundStyle(Theme.onSaffron)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .buttonStyle(.plain)
                    }
                }
                Text("Everyone sees it with the plan. \(noteDraft.count)/\(GroupSession.maxNoteLength)")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
            }
            .onAppear { noteDraft = session.note ?? "" }
            .onChange(of: session.note) { _, newValue in
                if !noteFocused { noteDraft = newValue ?? "" }
            }
            .onChange(of: noteDraft) { _, newValue in
                // A return key in a vertical field means "done", not a new line.
                if newValue.contains("\n") {
                    noteDraft = newValue.replacingOccurrences(of: "\n", with: "")
                    noteFocused = false
                } else if newValue.count > GroupSession.maxNoteLength {
                    noteDraft = String(newValue.prefix(GroupSession.maxNoteLength))
                }
            }
            .onChange(of: noteFocused) { _, focused in
                if !focused && noteIsDirty(session) { saveNote() }
            }
        } else if let note = session.trimmedNote {
            PlanNoteCard(note: note, author: session.createdByName)
        }
    }

    private func noteIsDirty(_ session: GroupSession) -> Bool {
        noteDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (session.trimmedNote ?? "")
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if let session = shownSession {
            Group {
                if session.status == .decided, let winner = session.winner {
                    HStack(spacing: 10) {
                        ShareLink(item: Self.planText(session, winner: winner, note: live.isOwner ? noteDraft : nil)) {
                            Label("Send everyone the plan", systemImage: "paperplane.fill")
                                .font(Theme.display(17))
                                .foregroundStyle(Theme.onSaffron)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .simultaneousGesture(TapGesture().onEnded { commitTaps += 1 })
                        // The same news as a picture, for group chats and stories.
                        SharePickButton(place: winner.place,
                                        context: .group(meetTime: session.meetTime)) {
                            Image(systemName: "photo")
                                .font(Theme.body(19, .semibold))
                                .foregroundStyle(Theme.text)
                                .frame(width: 56, height: 56)
                                .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .accessibilityLabel("Share as image")
                    }
                } else if live.isOwner {
                    Button {
                        if GroupWording.lockInWarning(session, totalVotes: live.tally.totalVotes) != nil { confirmLockIn = true } else { lockIn(session) }
                    } label: {
                        Text(session.mode == .vote ? "Lock it in" : "Spin it")
                            .font(Theme.display(17))
                            .foregroundStyle(Theme.onSaffron)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking || session.options.isEmpty)
                } else {
                    Text(GroupWording.whoDecides(session))
                        .font(Theme.body(14, .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.night)
        }
    }

    // MARK: Actions

    private func vote(for option: GroupOption, in session: GroupSession) {
        guard let name = Identity.displayName else {
            pendingVote = option
            showNamePrompt = true
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                if live.myVote == option.id {
                    try await GroupService.shared.removeVote(sessionID: session.id)
                } else {
                    try await GroupService.shared.vote(sessionID: session.id, optionID: option.id, displayName: name)
                }
            } catch { errorMessage = GroupService.message(for: error) }
        }
    }

    private func endGroup() {
        guard let session = live.session else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                live.stop()
                try await GroupService.shared.endSession(session)
                LeaveBy.cancel(sessionID: session.id)
                dismiss()
            } catch {
                errorMessage = GroupService.message(for: error)
                await live.start()
            }
        }
    }

    private func leaveGroup() {
        Task {
            do {
                try await GroupService.shared.leaveSession(sessionID)
                LeaveBy.cancel(sessionID: sessionID)
                dismiss()
            } catch { errorMessage = GroupService.message(for: error) }
        }
    }

    private func reopen(_ session: GroupSession) {
        Task {
            do {
                try await GroupService.shared.reopen(session: session)
                LeaveBy.cancel(sessionID: session.id)
            }
            catch { errorMessage = GroupService.message(for: error) }
        }
    }

    private func lockIn(_ session: GroupSession) {
        commitTaps += 1
        isWorking = true
        Task {
            defer { isWorking = false }
            do { _ = try await GroupService.shared.decide(session: session, votes: live.votes, ruledOut: live.ruledOutIDs) }
            catch { errorMessage = GroupService.message(for: error) }
        }
    }

    private func setMeetTime(_ date: Date) {
        timeTaps += 1
        Task {
            do { try await GroupService.shared.setMeetTime(sessionID: sessionID, date: date) }
            catch { errorMessage = GroupService.message(for: error) }
        }
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

    private func saveNote() {
        noteFocused = false
        let text = noteDraft
        Task {
            do { try await GroupService.shared.setNote(sessionID: sessionID, note: text) }
            catch { errorMessage = GroupService.message(for: error) }
        }
    }

    /// On the owner's phone, lock in automatically when the timer runs out.
    private func autoCloseWhenTimeIsUp() async {
        guard let session = live.session, let closesAt = session.closesAt,
              session.status == .open, live.isOwner else { return }
        let wait = closesAt.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        guard !Task.isCancelled, let current = live.session, current.status == .open else { return }
        _ = try? await GroupService.shared.decide(session: current, votes: live.votes, ruledOut: live.ruledOutIDs)
    }

    // MARK: Helpers

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    static func planText(_ session: GroupSession, winner: GroupOption, note: String? = nil) -> String {
        var text = "\(session.title): we’re going to \(winner.name)"
        if let time = session.meetTime {
            text += " \(MeetTimes.phrase(for: time))"
        }
        if let note = (note ?? session.note)?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            text += ".\nNote: \(note)"
        }
        let name = winner.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        text += ".\nDirections: https://maps.apple.com/?daddr=\(winner.latitude),\(winner.longitude)&q=\(name)"
        return text
    }
}

/// Sheet for adding a place to an open session, with the same filters as
/// Discover: radius, cuisines, diet, no fast food, and a name search.
private struct AddOptionView: View {
    let session: GroupSession
    var groupBlockedHashes: Set<String> = []

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var adding: String?

    /// You already picked, so choosing a place swaps it.
    private var isChanging: Bool {
        guard let uid = GroupService.shared.currentUserID else { return false }
        return session.pick(of: uid) != nil && !(session.mode == .vote && session.isOwned(by: uid))
    }

    private func savedPlaces(_ list: SavedList) -> [Place] {
        saved.filter { $0.list == list && $0.isShareable }.map { $0.asPlace(from: model.center) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger).listRowBackground(Color.clear)
                }
                GroupPlacePicker(
                    query: query,
                    center: model.center,
                    centerName: model.locationName,
                    favorites: savedPlaces(.favorites),
                    interested: savedPlaces(.interested),
                    startingFilters: PlacePickerFilters(model.searchArea),
                    startingNearby: model.places,
                    rules: model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories),
                    excludedIDs: Set(session.options.map(\.id)),
                    groupBlockedHashes: groupBlockedHashes,
                    sessionID: session.id,
                    search: model.placeSearch,
                    accessory: { .add(isBusy: adding == $0.id) },
                    isDisabled: { _ in adding != nil },
                    onTap: add
                )
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search restaurants or cravings")
            .navigationTitle(isChanging ? "Change your pick" : (session.mode == .spin ? "Add your pick" : "Suggest a place"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .presentationBackground(Theme.night)
    }

    private func add(_ place: Place) {
        let name = Identity.displayName ?? "Someone"
        adding = place.id
        errorMessage = nil
        Task {
            defer { adding = nil }
            do {
                try await GroupService.shared.addOption(sessionID: session.id, option: GroupOption(place: place, addedBy: name))
                dismiss()
            } catch let error as GroupError {
                errorMessage = GroupService.message(for: error)
            } catch {
                errorMessage = "Couldn’t add it. Voting may have closed, or the wheel is full (12 places)."
            }
        }
    }
}
