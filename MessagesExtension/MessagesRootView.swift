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
            .font(.system(size: 15, weight: .semibold))
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

/// Pick places from your Interested list and last nearby search, then send a vote.
struct NewVoteView: View {
    @Bindable var state: MessagesState

    @State private var selected: [Place] = []
    @State private var includeWebLink = true
    @State private var isSending = false
    @State private var errorMessage: String?

    private let maxOptions = 6

    private var interested: [Place] { filtered(SharedCache.loadInterested()) }
    private var nearby: [Place] {
        let ids = Set(interested.map(\.id))
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
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.saffron)
                        .frame(width: 44, height: 44)
                        .background(Theme.onSaffron, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start a dinner vote").font(Theme.display(18))
                        Text("Pick a few places, friends vote right here").font(.system(size: 12, weight: .medium))
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
                    if interested.isEmpty && nearby.isEmpty {
                        Text("Open ForkRoad and look around nearby first. Places you see there show up here.")
                            .foregroundStyle(Theme.muted)
                            .listRowBackground(Color.clear)
                    }
                    section("Interested list", interested)
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
                            MonogramTile(name: place.name, size: 34)
                            Text(place.name).foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isOn ? Theme.saffron : Theme.muted.opacity(0.5))
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.saffron)
                    }

                    if let winner = session.winner {
                        WinnerCard(option: winner,
                                   detail: session.meetTime.map { "Meet at \($0.formatted(date: .omitted, time: .shortened))" } ?? winner.category)
                        if let url = directionsURL(winner) {
                            Button { state.open(url: url) } label: {
                                Label("Directions", systemImage: "location.north.line")
                                    .font(.system(size: 15, weight: .bold))
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
                                          isEnabled: !isWorking) {
                                vote(option, session: session)
                            }
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
                            .disabled(isWorking || tally.totalVotes == 0)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.system(size: 13)).foregroundStyle(Theme.danger)
                    }
                } else if let error = live.errorMessage {
                    Text(error).foregroundStyle(Theme.danger)
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
    }

    private func vote(_ option: GroupOption, session: GroupSession) {
        guard let name = Identity.displayName else { return }
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
                // Refresh the bubble so the thread shows the new count.
                try? await Task.sleep(for: .milliseconds(400))
                if let current = live.session {
                    state.sendUpdate(current, tally: live.tally, memberCount: live.members.count)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func lockIn(_ session: GroupSession) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                _ = try await GroupService.shared.decide(session: session, votes: live.votes)
                try? await Task.sleep(for: .milliseconds(400))
                if let current = live.session {
                    state.sendUpdate(current, tally: live.tally, memberCount: live.members.count)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func directionsURL(_ option: GroupOption) -> URL? {
        let name = option.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?daddr=\(option.latitude),\(option.longitude)&q=\(name)")
    }
}
