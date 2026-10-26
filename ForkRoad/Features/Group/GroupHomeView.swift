import SwiftUI
import PickerCore

/// Group tab: start a pick, join with a code, or reopen a recent one.
struct GroupHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [String] = []
    @State private var showCreate = false
    @State private var showNamePrompt = false
    @State private var pendingAction: PendingAction?
    @State private var joinCode = ""
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var recentIDs = SharedCache.recentSessionIDs()

    private enum PendingAction { case create, join }

    var body: some View {
        NavigationStack(path: $path) { content }
            // Open a group from a notification or link.
            .onChange(of: model.pendingGroupSessionID, initial: true) {
                guard let id = model.pendingGroupSessionID else { return }
                model.pendingGroupSessionID = nil
                if path.last != id { path = [id] }
            }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Group pick")
                    Text("Decide together")
                        .font(Theme.display(34))
                        .foregroundStyle(Theme.text)
                }
                .padding(.top, 8)

                if !FirebaseSetup.isConfigured {
                    setupNotice
                } else {
                    startCard
                    joinCard
                    if let errorMessage {
                        Text(errorMessage).font(Theme.body(14)).foregroundStyle(Theme.danger)
                    }
                    recent
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.night)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { GroupLobbyView(sessionID: $0) }
        .sheet(isPresented: $showCreate) {
            CreateGroupView { session in
                showCreate = false
                recentIDs = SharedCache.recentSessionIDs()
                path.append(session.id)
                Task { await PushTokens.requestGroupAlerts() }
            }
        }
        // Continue only after the name sheet has fully closed; opening the
        // create sheet while it's still animating away gets ignored.
        .sheet(isPresented: $showNamePrompt, onDismiss: runPending) {
            NamePromptView { _ in showNamePrompt = false }
            .presentationDetents([.height(300)])
            .presentationBackground(Theme.night)
        }
        .onAppear { recentIDs = SharedCache.recentSessionIDs() }
    }

    // MARK: Sections

    private var setupNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Group voting needs Firebase", systemImage: "wrench.and.screwdriver")
                .font(Theme.body(16, .semibold))
                .foregroundStyle(Theme.text)
            Text("Add your GoogleService-Info.plist to the Config folder and rebuild. The README’s Firebase setup section walks through it in about 10 minutes.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .card()
    }

    private var startCard: some View {
        Button {
            withName(.create)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.2.fill")
                    .font(Theme.body(20, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 48, height: 48)
                    .background(Theme.onSaffron, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start a group pick").font(Theme.display(19))
                    Text("Vote or spin, then send everyone the plan").font(Theme.body(13, .medium))
                }
                Spacer()
                Image(systemName: "chevron.right").font(Theme.body(16, .bold))
            }
            .foregroundStyle(Theme.onSaffron)
            .padding(16)
            .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Got a code?")
                .font(Theme.body(15, .semibold))
                .foregroundStyle(Theme.text)
            HStack(spacing: 10) {
                TextField("K7Q·4MZ", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(Theme.code(20))
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Theme.text)
                    .accessibilityLabel("Join code")
                Button {
                    withName(.join)
                } label: {
                    if isJoining { ProgressView().tint(Theme.night) } else { Text("Join") }
                }
                .font(Theme.body(15, .bold))
                .foregroundStyle(Theme.night)
                .frame(width: 80, height: 50)
                .background(Theme.text, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .buttonStyle(.plain)
                .disabled(JoinCode.normalize(joinCode).count != 6 || isJoining)
            }
        }
        .padding(16)
        .card()
    }

    @ViewBuilder
    private var recent: some View {
        if !recentIDs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Recent")
                ForEach(recentIDs, id: \.self) { id in
                    RecentSessionRow(sessionID: id, open: { path.append(id) }) {
                        SharedCache.forgetSession(id)
                        recentIDs = SharedCache.recentSessionIDs()
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func withName(_ action: PendingAction) {
        pendingAction = action
        if Identity.displayName == nil { showNamePrompt = true } else { runPending() }
    }

    private func runPending() {
        guard let action = pendingAction, let name = Identity.displayName else { return }
        pendingAction = nil
        switch action {
        case .create:
            showCreate = true
        case .join:
            isJoining = true
            errorMessage = nil
            Task {
                defer { isJoining = false }
                do {
                    let session = try await GroupService.shared.findSession(joinCode: joinCode)
                    try await GroupService.shared.join(sessionID: session.id, displayName: name)
                    await PushTokens.requestGroupAlerts()
                    joinCode = ""
                    recentIDs = SharedCache.recentSessionIDs()
                    path.append(session.id)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

/// A recent session, loaded live so the title and status stay current.
private struct RecentSessionRow: View {
    let sessionID: String
    let open: () -> Void
    let remove: () -> Void
    @State private var live: LiveSession

    init(sessionID: String, open: @escaping () -> Void, remove: @escaping () -> Void) {
        self.sessionID = sessionID
        self.open = open
        self.remove = remove
        _live = State(initialValue: LiveSession(sessionID: sessionID))
    }

    var body: some View {
        Button {
            if live.session != nil { open() }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(live.session?.title ?? (live.errorMessage == nil ? "Loading…" : "No longer available"))
                        .font(Theme.body(16, .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted.opacity(0.6))
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
        .task { await live.start() }
        .onDisappear { live.stop() }
        .contextMenu {
            Button("Remove from Recent", systemImage: "trash", role: .destructive, action: remove)
        }
    }

    private var subtitle: String {
        guard let session = live.session else { return " " }
        if let winner = session.winner { return "Picked \(winner.name)" }
        return "\(session.options.count) options · \(live.members.count) in"
    }
}
