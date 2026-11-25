import SwiftUI
import PickerCore

/// Group tab: start a pick, join with a code, or reopen a recent one.
struct GroupHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [String] = []
    @State private var showCreate = false
    /// "Make it a group plan" from a spin: the plan starts with this place.
    @State private var startingPlace: Place?
    @State private var showNamePrompt = false
    @State private var pendingAction: PendingAction?
    @State private var joinCode = ""
    /// The empty state's "Got a code?" link opens the usual cards.
    @State private var showJoin = false
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var recentIDs = SharedCache.recentSessionIDs()
    /// One-time "New in 1.1" card for people who had the app before the tour.
    @AppStorage(TourPage.seenNewKey) private var seenNew = false
    @State private var showTour = false

    private enum PendingAction { case create, join }

    var body: some View {
        NavigationStack(path: $path) { content }
            // Open a group from a notification or link.
            .onChange(of: model.pendingGroupSessionID, initial: true) {
                guard let id = model.pendingGroupSessionID else { return }
                model.pendingGroupSessionID = nil
                if path.last != id { path = [id] }
            }
            // Spin → "Make it a group plan".
            .onChange(of: model.pendingPlanPlace?.id, initial: true) {
                guard let place = model.pendingPlanPlace else { return }
                model.pendingPlanPlace = nil
                path = []
                startingPlace = place
                withName(.create)
            }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Group plan")
                    Text("Decide together")
                        .font(Theme.display(34))
                        .foregroundStyle(Theme.text)
                }
                .padding(.top, 8)

                if FirebaseSetup.isConfigured && !seenNew {
                    newInThisVersion
                }

                if !FirebaseSetup.isConfigured {
                    setupNotice
                } else if recentIDs.isEmpty && !showJoin {
                    // First time here: a friendly empty state instead of two cards.
                    EmptyState(
                        art: .chat,
                        title: "No more “idk, you pick”",
                        message: "Start a plan, send it to the group chat, and let everyone vote or add a pick. Friends don’t need the app.",
                        primary: ("Start a group plan", { withName(.create) }),
                        secondary: ("Got a code? Join the group", { withAnimation(.snappy) { showJoin = true } })
                    )
                    .padding(.top, 40)
                } else {
                    if recentIDs.isEmpty { HintCard(.groupStart) }
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
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.night)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { GroupLobbyView(sessionID: $0) }
        .sheet(isPresented: $showCreate, onDismiss: { startingPlace = nil }) {
            CreateGroupView(startingPlace: startingPlace) { session in
                showCreate = false
                startingPlace = nil
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
        .fullScreenCover(isPresented: $showTour) {
            OnboardingView(pages: TourPage.groups) { showTour = false }
                .environment(model)
        }
    }

    /// "New in 1.1": opens the tour's group pages. Shown once.
    private var newInThisVersion: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(Theme.body(18, .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 40, height: 40)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("NEW IN 1.1").font(Theme.body(11, .heavy)).tracking(0.8).foregroundStyle(Theme.accentText)
                Text("Group plans got better").font(Theme.body(16, .semibold)).foregroundStyle(Theme.text)
                Text("Group filters, “On my way” with arrival times, and a Lock Screen countdown you control.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Take a look") { showTour = true; seenNew = true }
                    .font(Theme.body(14, .bold))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 36)
            }
            Spacer(minLength: 0)
            Button { withAnimation(.snappy) { seenNew = true } } label: {
                Image(systemName: "xmark")
                    .font(Theme.body(13, .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .card()
    }

    // MARK: Sections

    private var setupNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Only in a developer build missing its Firebase config (a Release
            // build without it fails to compile), so users never see setup steps.
            Label("Group plans aren’t available right now", systemImage: "person.3")
                .font(Theme.body(16, .semibold))
                .foregroundStyle(Theme.text)
            Text("You can still discover, spin, and save places. Check back soon.")
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
                    Text("Start a group plan").font(Theme.display(19))
                    Text("Vote or spin, then send everyone the plan").font(Theme.body(13, .medium))
                }
                Spacer()
                Image(systemName: "chevron.right").font(Theme.body(16, .bold))
            }
            .foregroundStyle(Theme.onSaffron)
            .padding(16)
            .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.pressable)
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
                .buttonStyle(.pressable)
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
        Hint.groupStart.dismiss()
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
            if live.session != nil { open() } else if live.isGone { remove() }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(live.session?.title ?? (live.isGone ? "This group has ended" : "Loading…"))
                        .font(Theme.body(16, .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: live.isGone ? "xmark.circle" : "chevron.right")
                    .foregroundStyle(Theme.muted.opacity(0.6))
                    .accessibilityLabel(live.isGone ? "Remove" : "")
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.pressable)
        .task { await live.start() }
        .onDisappear { live.stop() }
        .contextMenu {
            Button("Remove from Recent", systemImage: "trash", role: .destructive, action: remove)
        }
    }

    private var subtitle: String {
        if live.isGone { return "Tap to remove it from Recent" }
        guard let session = live.session else { return live.errorMessage ?? " " }
        if let winner = session.winner { return "Picked \(winner.name)" }
        return "\(plural(session.options.count, "option")) · \(live.members.count) in"
    }
}
