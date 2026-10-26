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

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedTab) {
            NavigationStack { DiscoverView() }
                .tabItem { Label("Discover", systemImage: "safari") }
                .tag(AppTab.discover)

            NavigationStack { SpinView() }
                .tabItem { Label("Spin", systemImage: "dice") }
                .tag(AppTab.spin)

            NavigationStack { ListsView() }
                .tabItem { Label("Lists", systemImage: "heart") }
                .tag(AppTab.lists)

            GroupHomeView()  // owns its NavigationStack so it can push new sessions
                .tabItem { Label("Group", systemImage: "person.2") }
                .tag(AppTab.group)

            NavigationStack { TripsView() }
                .tabItem { Label("Trips", systemImage: "globe.americas") }
                .tag(AppTab.trips)
        }
        .toolbarBackground(Theme.night, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task { model.start() }
        // Keep the widget's, Siri's, and the iMessage app's copies of your lists current.
        .onChange(of: cacheKey, initial: true) { refreshSharedCaches() }
        .onOpenURL { url in
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
            if followUp == nil, UserDefaults.standard.bool(forKey: "didOnboard") {
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

    private func handle(_ link: String) {
        switch link {
        case "spin": model.selectedTab = .spin
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
        saved.map { "\($0.placeID)|\($0.listRaw)|\($0.skipInSpins)" }
            + blockedPlaces.map(\.placeID) + blockedCategories.map(\.name)
    }

    private func refreshSharedCaches() {
        // Places left out of spins aren't offered by the widget or Siri either.
        let spinnable = saved.filter { !$0.skipInSpins }
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
        .buttonStyle(.plain)
        .accessibilityHint(note)
    }

    private func reply(_ answer: VisitFollowUp.Answer) {
        VisitFollowUp.answer(visit, answer, in: context)
        dismiss()
    }
}
