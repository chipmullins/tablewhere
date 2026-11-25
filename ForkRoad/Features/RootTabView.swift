import SwiftUI
import SwiftData
import WidgetKit
import PickerCore

struct RootTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]

    @State private var followUp: Visit?

    init() {
        // The floating pill replaces the system tab bar everywhere, pushed screens too.
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedTab) {
            NavigationStack { DiscoverView() }
                .floatingTabBarClearance()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.discover)

            NavigationStack { SpinView() }
                .floatingTabBarClearance()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.spin)

            NavigationStack { ListsView() }
                .floatingTabBarClearance()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.lists)

            GroupHomeView()  // owns its NavigationStack so it can push new sessions
                .floatingTabBarClearance()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.group)

        }
        // Big text, but not so big the fixed-size pieces (Spin button, reel) break.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        // The sleek tab bar floats over every tab (the system one is hidden).
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $model.selectedTab)
                .padding(.bottom, 8)
                .ignoresSafeArea(.keyboard)
        }
        .overlay(alignment: .bottom) { UndoToastHost() }
        // A toast from one tab doesn't follow you to the next.
        .onChange(of: model.selectedTab) { UndoCenter.shared.hide() }
        .task { model.start() }
        // Keep the widget's, Siri's, and the iMessage app's copies of your lists current.
        .onChange(of: cacheKey, initial: true) { refreshSharedCaches() }
        .onOpenURL { url in
            // https://forkroad-app.web.app/v/<id>: a group link (Universal Link),
            // opened in the app instead of the web page.
            if url.scheme == "https", url.host == AppConfig.webHost {
                let parts = url.pathComponents.filter { $0 != "/" }
                if parts.count >= 2, parts[0] == "v" { handle("group:\(parts[1])") }
                return
            }
            // forkroad://place?d=<base64url JSON>: the widget's pick, opened on Discover.
            if url.host == "place", let place = Self.place(from: url) {
                model.selectedTab = .discover
                model.pendingPlace = place
                return
            }
            // forkroad://spin?go=1: open Spin and spin (Control Center, Action Button, Siri).
            if url.host == "spin", URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.contains(where: { $0.name == "go" && $0.value == "1" }) == true {
                handle(SpinLink.autoSpin)
                return
            }
            // forkroad://spin, forkroad://discover, forkroad://lists, forkroad://group/<id>
            let parts = [url.host ?? ""] + url.pathComponents.filter { $0 != "/" }
            handle(parts.first == "group" && parts.count > 1 ? "group:\(parts[1])" : (parts.first ?? ""))
        }
        .onReceive(NotificationCenter.default.publisher(for: DeepLink.notification)) { _ in
            if let link = DeepLink.take() { handle(link) }
        }
        .onChange(of: scenePhase, initial: true) {
            guard scenePhase == .active else { return }
            if let link = DeepLink.take() { handle(link) }
            UsageStats.recordActiveDevice()
            // Keep "time to leave" reminders right for decided groups.
            Task { await LeaveBy.refreshAll(model) }
            if followUp == nil, VisitFollowUp.remindersOn, UserDefaults.standard.bool(forKey: "didOnboard") {
                followUp = VisitFollowUp.pending(in: context)
            }
        }
        .sheet(item: $followUp) { visit in
            HowWasItSheet(visit: visit)
                .presentationDetents([.height(380)])
                .presentationBackground(Theme.night)
        }
    }

    // MARK: Deep links

    private static func place(from url: URL) -> Place? {
        guard var text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "d" })?.value else { return nil }
        text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text += "=" }
        guard let data = Data(base64Encoded: text) else { return nil }
        return try? JSONDecoder().decode(Place.self, from: data)
    }

    private func handle(_ link: String) {
        switch link {
        case "spin": model.selectedTab = .spin
        case SpinLink.autoSpin:
            model.selectedTab = .spin
            model.eatIn = false  // the widget, Control Center, and Siri spin restaurants
            model.pendingSpin = true
        case "discover": model.selectedTab = .discover
        case "lists": model.selectedTab = .lists
        case let group where group.hasPrefix("group:"):
            model.selectedTab = .group
            model.pendingGroupSessionID = String(group.dropFirst("group:".count))
        default: break
        }
    }

    // MARK: Shared caches (widget, Siri, iMessage)

    private var cacheKey: [String] {
        saved.map { "\($0.placeID)|\($0.listRaw)|\($0.skipInSpins)|\($0.name)|\($0.hasExactLocation)" }
            + blockedPlaces.map(\.placeID) + blockedCategories.map(\.name)
    }

    private func refreshSharedCaches() {
        // Places left out of spins aren't offered by the widget or Siri either.
        // Your own places without an address stay out too: the iMessage app
        // uses this list for group picks, and they have no real location.
        let spinnable = saved.filter { !$0.skipInSpins && $0.isShareable }
        SharedCache.saveFavorites(spinnable.filter { $0.list == .favorites }.map { $0.asPlace(from: model.center) })
        SharedCache.saveInterested(spinnable.filter { $0.list == .interested }.map { $0.asPlace(from: model.center) })
        SharedCache.saveBlocked(placeIDs: blockedPlaces.map(\.placeID), categories: blockedCategories.map(\.name))
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// "How was it?" after a visit: files the answer into your lists.
struct HowWasItSheet: View {
    let visit: Visit
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            MonogramTile(name: visit.name, category: visit.category, size: 64)
                .padding(.top, 8)
            VStack(spacing: 6) {
                Text("How was \(visit.name)?")
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                Text("Your answer updates your lists.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 10) {
                answerButton("Loved it", icon: "heart.fill", note: "Adds to Favorites", answer: .loved, filled: true)
                answerButton("It was fine", icon: "hand.thumbsup", note: "No changes", answer: .fine, filled: false)
                answerButton("Never again", icon: "nosign", note: "Blacklists it", answer: .never, filled: false)
            }
            Button("We didn’t go") { reply(.skipped) }
                .font(Theme.body(15, .semibold))
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 20)
        .sensoryFeedback(.success, trigger: visit.answeredAt)
        .onDisappear {
            // Swiped away: count it as skipped so it doesn't come back every launch.
            if visit.answeredAt == nil { VisitFollowUp.answer(visit, .skipped, in: context) }
        }
    }

    private func answerButton(_ title: String, icon: String, note: String,
                              answer: VisitFollowUp.Answer, filled: Bool) -> some View {
        Button { reply(answer) } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                Text(title).font(Theme.body(14, .bold))
                Text(note).font(Theme.body(11)).opacity(0.75)
            }
            .foregroundStyle(filled ? Theme.onSaffron : (answer == .never ? Theme.danger : Theme.text))
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(filled ? Theme.saffron : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(filled ? .clear : Theme.hairline))
        }
        .buttonStyle(.pressable)
        .accessibilityHint(note)
    }

    private func reply(_ answer: VisitFollowUp.Answer) {
        VisitFollowUp.answer(visit, answer, in: context)
        dismiss()
    }
}
