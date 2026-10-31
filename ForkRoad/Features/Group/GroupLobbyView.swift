import SwiftUI
import SwiftData
import PickerCore

/// A live group pick: invite, vote (or add places for a spin), lock it in,
/// then set a meeting time and send everyone the plan.
struct GroupLobbyView: View {
    let sessionID: String

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmEnd = false
    @State private var confirmLeave = false
    @State private var live: LiveSession
    @State private var showAddPlace = false
    @State private var browserURL: URL?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var showTimePicker = false
    @State private var noteDraft = ""
    @FocusState private var noteFocused: Bool

    init(sessionID: String) {
        self.sessionID = sessionID
        _live = State(initialValue: LiveSession(sessionID: sessionID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let session = live.session {
                    header(session)
                    if session.status == .decided, let winner = session.winner {
                        decided(session, winner: winner)
                    } else {
                        deciding(session)
                    }
                } else if live.errorMessage != nil {
                    StateCard(icon: "flag.checkered",
                              title: "This group pick has ended",
                              message: "The person who started it ended it, or it no longer exists.",
                              action: ("Back to Group", { SharedCache.forgetSession(sessionID); dismiss() }))
                        .padding(.top, 40)
                } else {
                    ProgressView().tint(Theme.muted).frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.night)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let session = live.session {
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
        .confirmationDialog("End this group pick?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End for everyone", role: .destructive) { endGroup() }
        } message: {
            Text("Votes and the join code are deleted, and everyone’s told it has ended.")
        }
        .confirmationDialog("Leave this group pick?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { leaveGroup() }
        } message: {
            Text("Your vote is removed. You can rejoin with the code.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil },
                                                             set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .task { await live.start() }
        .task(id: live.session?.closesAt) { await autoCloseWhenTimeIsUp() }
        .sheet(isPresented: $showAddPlace) {
            if let session = live.session { AddOptionView(session: session) }
        }
        .sheet(item: $browserURL) { SafariView(url: $0).ignoresSafeArea() }
        .sensoryFeedback(.success, trigger: live.session?.winnerID)
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
                              message: Text("Help pick where we eat! Vote here, or join in ForkRoad with code \(JoinCode.display(session.joinCode)).")) {
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
        if session.status == .decided { return "Locked in by \(session.createdByName)" }
        switch session.mode {
        case .vote:
            let waiting = max(0, live.members.count - live.votes.count)
            return waiting == 0 ? "Everyone has voted" : "Waiting on \(waiting) vote\(waiting == 1 ? "" : "s")"
        case .spin:
            return "\(session.options.count) places in the wheel"
        }
    }

    // MARK: Deciding

    @ViewBuilder
    private func deciding(_ session: GroupSession) -> some View {
        if let closesAt = session.closesAt, session.mode == .vote {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(closesAt.timeIntervalSince(context.date)))
                Label(remaining > 0 ? "Closes in \(remaining / 60):\(String(format: "%02d", remaining % 60))" : "Voting closed",
                      systemImage: "timer")
                    .font(Theme.body(13, .bold))
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Theme.accentSoft, in: Capsule())
            }
        }

        let tally = live.tally
        let slots = max(live.members.count, tally.totalVotes, 1)
        Label(session.mode == .vote
              ? (live.myVote == nil ? "Tap a place to cast your vote" : "Tap another place to change your vote")
              : "Everyone adds places, then \(live.isOwner ? "you spin" : "\(session.createdByName) spins")",
              systemImage: session.mode == .vote ? "hand.tap" : "dice")
            .font(Theme.body(14, .semibold))
            .foregroundStyle(Theme.accentText)
        VStack(spacing: 10) {
            ForEach(session.options) { option in
                VoteOptionRow(
                    option: option,
                    votes: session.mode == .vote ? tally.count(for: option.id) : 0,
                    totalSlots: slots,
                    voters: session.mode == .vote ? (tally.votersByOption[option.id] ?? []) : [],
                    isMine: live.myVote == option.id,
                    isLeading: session.mode == .vote && tally.leader == option.id,
                    isEnabled: session.mode == .vote && !isWorking,
                    showsVotes: session.mode == .vote
                ) {
                    vote(for: option, in: session)
                }
            }
        }

        AddPlaceButton(session: session, userID: GroupService.shared.currentUserID) { showAddPlace = true }

        if session.mode == .vote {
            Label("If it ends in a tie, the app picks fairly between the tied places.", systemImage: "shuffle")
                .font(Theme.body(13))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Decided

    @ViewBuilder
    private func decided(_ session: GroupSession, winner: GroupOption) -> some View {
        let count = live.tally.count(for: winner.id)
        WinnerCard(option: winner,
                   detail: session.mode == .vote ? "\(count) of \(live.tally.totalVotes) votes · \(winner.category)" : "Picked by the spin · \(winner.category)")

        HStack(spacing: 8) {
            ActionTile(title: "Directions", systemImage: "location.north.line", tint: Theme.accentText, background: Theme.surface) {
                PlaceLinks.openDirections(winner.place)
                VisitFollowUp.record(winner.place, in: context)
            }
            ActionTile(title: "Call", systemImage: "phone", tint: Theme.accentText, background: Theme.surface) {
                if let url = PlaceLinks.phoneURL(winner.place) { openURL(url) }
            }
            .disabled(winner.phoneNumber == nil)
            .opacity(winner.phoneNumber == nil ? 0.4 : 1)
            ActionTile(title: "Menu", systemImage: "menucard", tint: Theme.accentText, background: Theme.surface) {
                browserURL = winner.place.websiteURL
            }
            .disabled(winner.websiteURL == nil)
            .opacity(winner.websiteURL == nil ? 0.4 : 1)
        }

        meetTimeSection(session)
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
                    meetButton(isCustom ? (session.meetTime?.formatted(date: .omitted, time: .shortened) ?? "Custom")
                                        : "Custom…",
                               systemImage: "clock", isOn: isCustom) {
                        showTimePicker = true
                    }
                }
                .sheet(isPresented: $showTimePicker) {
                    MeetTimePickerSheet(initial: session.meetTime ?? slots.first ?? .now) { setMeetTime($0) }
                }
            } else {
                Text(session.meetTime.map { $0.formatted(date: .omitted, time: .shortened) } ?? "\(session.createdByName) hasn’t set a time yet")
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
        if let session = live.session {
            Group {
                if session.status == .decided, let winner = session.winner {
                    ShareLink(item: Self.planText(session, winner: winner, note: live.isOwner ? noteDraft : nil)) {
                        Label("Send everyone the plan", systemImage: "paperplane.fill")
                            .font(Theme.display(17))
                            .foregroundStyle(Theme.onSaffron)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                } else if live.isOwner {
                    Button { lockIn(session) } label: {
                        Text(session.mode == .vote ? "Lock it in" : "Spin it")
                            .font(Theme.display(17))
                            .foregroundStyle(Theme.onSaffron)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking || session.options.isEmpty)
                } else {
                    Text(session.mode == .vote ? "\(session.createdByName) will lock in the result" : "\(session.createdByName) will spin when everyone’s ready")
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
            errorMessage = "Add your name in Settings so friends can see your vote."
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
            } catch { errorMessage = error.localizedDescription }
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
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                await live.start()
            }
        }
    }

    private func leaveGroup() {
        Task {
            do {
                try await GroupService.shared.leaveSession(sessionID)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func reopen(_ session: GroupSession) {
        Task {
            do { try await GroupService.shared.reopen(session: session) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func lockIn(_ session: GroupSession) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do { _ = try await GroupService.shared.decide(session: session, votes: live.votes) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func setMeetTime(_ date: Date) {
        Task {
            do { try await GroupService.shared.setMeetTime(sessionID: sessionID, date: date) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func saveNote() {
        noteFocused = false
        let text = noteDraft
        Task {
            do { try await GroupService.shared.setNote(sessionID: sessionID, note: text) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    /// On the owner's phone, lock in automatically when the timer runs out.
    private func autoCloseWhenTimeIsUp() async {
        guard let session = live.session, let closesAt = session.closesAt,
              session.status == .open, live.isOwner else { return }
        let wait = closesAt.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        guard !Task.isCancelled, let current = live.session, current.status == .open else { return }
        _ = try? await GroupService.shared.decide(session: current, votes: live.votes)
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
            text += " at \(time.formatted(date: .omitted, time: .shortened))"
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

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var adding: String?

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
                    favorites: savedPlaces(.favorites),
                    interested: savedPlaces(.interested),
                    startingFilters: PlacePickerFilters(model.searchArea),
                    startingNearby: model.places,
                    rules: model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories),
                    excludedIDs: Set(session.options.map(\.id)),
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
            .navigationTitle(session.mode == .spin ? "Add your pick" : "Suggest a place")
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
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Couldn’t add it. Voting may have closed, or the wheel is full (12 places)."
            }
        }
    }
}
