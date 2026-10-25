import SwiftUI
import SwiftData
import PickerCore

/// A live group pick: invite, vote (or add places for a spin), lock it in,
/// then set a meeting time and send everyone the plan.
struct GroupLobbyView: View {
    let sessionID: String

    @Environment(\.openURL) private var openURL
    @State private var live: LiveSession
    @State private var showAddPlace = false
    @State private var browserURL: URL?
    @State private var errorMessage: String?
    @State private var isWorking = false

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
                    if let errorMessage {
                        Text(errorMessage).font(.system(size: 14)).foregroundStyle(Theme.danger)
                    }
                } else if let error = live.errorMessage {
                    Text(error).foregroundStyle(Theme.danger).padding(.top, 40)
                } else {
                    ProgressView().tint(Theme.muted).frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.night)
        .navigationBarTitleDisplayMode(.inline)
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
                    Text("CODE").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                    Text(JoinCode.display(session.joinCode))
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(statusLine(session))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if let url = GroupLinks.webURL(sessionID: session.id, host: AppConfig.webHost) {
                    ShareLink(item: url,
                              subject: Text(session.title),
                              message: Text("Help pick where we eat! Vote here, or join in ForkRoad with code \(JoinCode.display(session.joinCode)).")) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
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
                    .font(.system(size: 13, weight: .bold))
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.saffron)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color(hex: 0x221C12), in: Capsule())
            }
        }

        let tally = live.tally
        let slots = max(live.members.count, tally.totalVotes, 1)
        VStack(spacing: 10) {
            ForEach(session.options) { option in
                VoteOptionRow(
                    option: option,
                    votes: session.mode == .vote ? tally.count(for: option.id) : 0,
                    totalSlots: slots,
                    voters: session.mode == .vote ? (tally.votersByOption[option.id] ?? []) : [],
                    isMine: live.myVote == option.id,
                    isLeading: session.mode == .vote && tally.leader == option.id,
                    isEnabled: session.mode == .vote && !isWorking
                ) {
                    vote(for: option, in: session)
                }
            }
        }

        Button { showAddPlace = true } label: {
            Label("Add a place", systemImage: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 50)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])).foregroundStyle(Theme.muted.opacity(0.4)))
        }
        .buttonStyle(.plain)

        if session.mode == .vote {
            Label("If it ends in a tie, the app picks fairly between the tied places.", systemImage: "shuffle")
                .font(.system(size: 13))
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
            ActionTile(title: "Directions", systemImage: "location.north.line", tint: Theme.saffron, background: Theme.surface) {
                PlaceLinks.openDirections(winner.place)
            }
            ActionTile(title: "Call", systemImage: "phone", tint: Theme.saffron, background: Theme.surface) {
                if let url = PlaceLinks.phoneURL(winner.place) { openURL(url) }
            }
            .disabled(winner.phoneNumber == nil)
            .opacity(winner.phoneNumber == nil ? 0.4 : 1)
            ActionTile(title: "Menu", systemImage: "menucard", tint: Theme.saffron, background: Theme.surface) {
                browserURL = winner.place.websiteURL
            }
            .disabled(winner.websiteURL == nil)
            .opacity(winner.websiteURL == nil ? 0.4 : 1)
        }

        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: live.isOwner ? "Meet at" : "Meeting time")
            if live.isOwner {
                HStack(spacing: 8) {
                    ForEach(Self.meetSlots(), id: \.self) { slot in
                        let isOn = session.meetTime.map { abs($0.timeIntervalSince(slot)) < 60 } ?? false
                        Button(slot.formatted(date: .omitted, time: .shortened)) { setMeetTime(slot) }
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(isOn ? Theme.night : Theme.text)
                            .background(isOn ? Theme.text : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .buttonStyle(.plain)
                    }
                }
            } else {
                Text(session.meetTime.map { $0.formatted(date: .omitted, time: .shortened) } ?? "\(session.createdByName) hasn’t set a time yet")
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.text)
            }
        }
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if let session = live.session {
            Group {
                if session.status == .decided, let winner = session.winner {
                    ShareLink(item: Self.planText(session, winner: winner)) {
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
                        .font(.system(size: 14, weight: .semibold))
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
        guard let name = Identity.displayName else { return }
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

    /// The next four half-hour slots, starting at least 20 minutes out.
    static func meetSlots(from now: Date = .now) -> [Date] {
        let calendar = Calendar.current
        let start = now.addingTimeInterval(20 * 60)
        let minute = calendar.component(.minute, from: start)
        let roundUp = minute == 0 || minute == 30 ? 0 : (minute < 30 ? 30 - minute : 60 - minute)
        let first = calendar.date(byAdding: .minute, value: roundUp, to: start) ?? start
        let clean = calendar.date(bySetting: .second, value: 0, of: first) ?? first
        return (0..<4).compactMap { calendar.date(byAdding: .minute, value: $0 * 30, to: clean) }
    }

    static func planText(_ session: GroupSession, winner: GroupOption) -> String {
        var text = "\(session.title): we’re going to \(winner.name)"
        if let time = session.meetTime {
            text += " at \(time.formatted(date: .omitted, time: .shortened))"
        }
        let name = winner.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        text += ".\nDirections: https://maps.apple.com/?daddr=\(winner.latitude),\(winner.longitude)&q=\(name)"
        return text
    }
}

/// Sheet for adding another place to an open session.
private struct AddOptionView: View {
    let session: GroupSession

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]
    @State private var errorMessage: String?

    private var candidates: [Place] {
        let taken = Set(session.options.map(\.id))
        let rules = model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories)
        var seen = Set<String>()
        let all = saved.map { $0.asPlace(from: model.center) } + model.places
        return Randomizer.eligible(all, rules: rules)
            .filter { !taken.contains($0.id) && seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger)
                }
                ForEach(candidates) { place in
                    Button { add(place) } label: {
                        HStack(spacing: 12) {
                            MonogramTile(name: place.name, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).foregroundStyle(Theme.text)
                                Text("\(place.category) · \(place.distanceLabel)")
                                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "plus.circle").foregroundStyle(Theme.saffron)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .presentationBackground(Theme.night)
    }

    private func add(_ place: Place) {
        let name = Identity.displayName ?? "Someone"
        Task {
            do {
                try await GroupService.shared.addOption(sessionID: session.id, option: GroupOption(place: place, addedBy: name))
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
