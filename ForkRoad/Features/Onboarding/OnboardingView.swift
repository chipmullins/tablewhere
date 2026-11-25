import SwiftUI
import UserNotifications

/// The tour (1.1): what Tablewhere does, with a focus on groups, then
/// location and notifications, each asked with its reason. New installs see
/// all of it; Settings → Take the tour replays it; existing users get the
/// group pages from a one-time "New in 1.1" card on the Group tab.
/// Swipeable, Skip on every page, Reduce Motion friendly.
enum TourPage: Int, CaseIterable, Identifiable {
    case welcome, spin, lists, groupWays, groupJoin, plans, permissions
    var id: Int { rawValue }

    /// The pages the "New in 1.1" card opens.
    static let groups: [TourPage] = [.groupWays, .groupJoin, .plans]
}

struct OnboardingView: View {
    var pages: [TourPage] = TourPage.allCases
    var onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var showCityPicker = false
    @State private var locationDenied = false
    @State private var isAsking = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var askedNotifications = false
    @State private var skippedTour = false

    private var page: TourPage { pages[min(index, pages.count - 1)] }
    private var isLast: Bool { index >= pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page != .permissions {
                    Button("Skip", action: skip)
                        .font(Theme.body(15, .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.trailing, 12)
                        .accessibilityHint(pages.contains(.permissions) ? "Goes to the last step" : "Closes the tour")
                }
            }
            .frame(height: 48)

            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.offset) { offset, page in
                    content(for: page).tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? nil : .snappy, value: index)

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Theme.saffron : Theme.track)
                        .frame(width: i == index ? 22 : 8, height: 8)
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: index)
            .padding(.bottom, 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(index + 1) of \(pages.count)")
        }
        .background(Theme.night.ignoresSafeArea())
        .sheet(isPresented: $showCityPicker, onDismiss: {
            // Picked a city (or "Current location" in the picker): on to alerts. Backed out: stay here.
            if model.hasLocation { locationDenied = false; afterLocation() }
        }) {
            LocationPickerView()
        }
        .task { await refreshNotificationStatus() }
    }

    // MARK: Pages

    @ViewBuilder
    private func content(for page: TourPage) -> some View {
        switch page {
        case .welcome:
            stepPage(
                art: AnyView(ForkMark().frame(width: 128, height: 128)),
                titleView: AnyView(WelcomeTitle()),
                title: "Where to eat? Let the table decide.",
                text: "Spin when you can’t decide where to eat out, or what to cook in. Then pick with friends.",
                primary: ("Take a quick look", next),
                footer: AnyView(
                    VStack(spacing: 4) {
                        Wordmark(size: 20)
                        Text("Created by Chip Mullins")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.muted.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                )
            )
        case .spin:
            stepPage(art: AnyView(TourSpinMock()), title: "Tap to spin",
                     text: "It picks from places near you. Switch to eating in to spin your own home meals, and use filters for a cuisine, a diet, or no fast food.",
                     primary: ("Next", next))
        case .lists:
            stepPage(art: AnyView(TourListsMock()), title: "Keep your places",
                     text: "Find what’s around, then save it: favorites you love, places to try, meals you make at home, and a blacklist the spin always skips.",
                     primary: ("Next", next))
        case .groupWays:
            stepPage(art: AnyView(TourGroupWaysMock()), title: "Four ways to decide together",
                     text: "Vote on a few places, spin everyone’s picks, let the wheel surprise you, or just pick and send the plan.",
                     primary: ("Next", next))
        case .groupJoin:
            stepPage(art: AnyView(TourJoinMock()), title: "Friends join from a link",
                     text: "Send it to the group chat. No app needed: they vote or add a pick in any browser. You see “3 of 6 picks in,” and hear when everyone’s in.",
                     primary: ("Next", next))
        case .plans:
            stepPage(art: AnyView(TourPlanMock()), title: "Then make it a plan",
                     text: "Set a time and see who’s coming. Tablewhere tells you when to leave, puts a countdown on your Lock Screen, and lets the group know when you’re on your way.",
                     primary: isLast ? ("Done", finish) : ("Next", next))
        case .permissions:
            permissionsPage
        }
    }

    /// Location first (or a city instead), then notifications, each with why.
    private var permissionsPage: some View {
        // Answered (or a city picked): a fresh "allow" may not have a fix yet.
        let locationOn = model.hasLocation || (!model.location.isDenied && model.location.authorization != .notDetermined)
        let needsLocation = !locationOn && !locationDenied
        let needsAlerts = !needsLocation && !locationDenied && notificationStatus == .notDetermined && !askedNotifications
        let title: String
        let text: String
        let primary: (String, () -> Void)
        var secondary: (String, () -> Void)?
        if locationDenied {
            title = "No problem"
            text = "Location is off, so pick a city or neighborhood to search instead. You can turn location on later in Settings."
            primary = ("Pick a city", { showCityPicker = true })
        } else if needsLocation {
            title = "Find food near you"
            text = "Tablewhere uses your location only while you’re using the app, to find restaurants around you and work out when to leave for group plans. You can also pick any city instead."
            primary = (isAsking ? "One sec…" : "Use my location", askForLocation)
            secondary = ("Pick a city instead", { showCityPicker = true })
        } else if needsAlerts {
            title = "Know when it’s decided"
            text = "Turn on alerts to hear when everyone’s pick is in, what the group chose, when to leave, and when friends are on their way."
            primary = ("Turn on alerts", askForAlerts)
            secondary = ("Not now", finish)
        } else {
            title = "You’re all set"
            text = "Location: \(locationOn ? "on" : "pick a city anytime"). Alerts: \(notificationStatus == .authorized || notificationStatus == .provisional ? "on" : "off (turn them on in Settings)")."
            primary = ("Let’s eat", finish)
        }
        return stepPage(
            art: AnyView(symbolArt(needsAlerts ? "bell.badge.fill" : "location.fill")),
            title: title, text: text, primary: primary, secondary: secondary,
            footer: AnyView(
                Text("Tablewhere counts anonymous daily totals (like spins) to get better. Turn it off anytime in Settings.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            )
        )
    }

    // MARK: Building blocks

    private func stepPage(art: AnyView, titleView: AnyView? = nil, title: String, text: String,
                          primary: (String, () -> Void), secondary: (String, () -> Void)? = nil,
                          footer: AnyView? = nil) -> some View {
        // Normal sizes: the page fills the screen, with Spacers centering the
        // copy and pinning the buttons low. If that doesn't fit (large Dynamic
        // Type), the same content scrolls, with fixed gaps instead of Spacers.
        ViewThatFits(in: .vertical) {
            stepContent(art: art, titleView: titleView, title: title, text: text,
                        primary: primary, secondary: secondary, footer: footer, flexible: true)
            ScrollView {
                stepContent(art: art, titleView: titleView, title: title, text: text,
                            primary: primary, secondary: secondary, footer: footer, flexible: false)
                    .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func stepContent(art: AnyView, titleView: AnyView?, title: String, text: String,
                             primary: (String, () -> Void), secondary: (String, () -> Void)?,
                             footer: AnyView?, flexible: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if flexible { Spacer(minLength: 0) }
            art
                .frame(maxWidth: .infinity, alignment: .center)
                .allowsHitTesting(false)
            if let titleView {
                titleView
            } else {
                Text(title)
                    .font(Theme.display(34))
                    .tracking(-1)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(text)
                .font(Theme.body(16))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if flexible { Spacer(minLength: 0) } else { Color.clear.frame(height: 8) }
            primaryButton(primary.0, action: primary.1)
            if let secondary {
                Button(secondary.0, action: secondary.1)
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else if flexible {
                // Keeps the pages' layout the same height at normal sizes.
                Color.clear.frame(height: 44)
            }
            if let footer { footer }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(.sleekSaffron)
    }

    private func symbolArt(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(Theme.accentText)
            .frame(width: 84, height: 84)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: Actions

    private func next() {
        guard !isLast else { return finish() }
        if reduceMotion { index += 1 } else { withAnimation(.snappy) { index += 1 } }
    }

    /// The first run still needs location (or a city): Skip goes to that
    /// step. A replay, or the group pages alone, just closes.
    private func skip() {
        skippedTour = true
        if let last = pages.firstIndex(of: .permissions), index < last {
            if reduceMotion { index = last } else { withAnimation(.snappy) { index = last } }
        } else {
            finish()
        }
    }

    /// Shows the system prompt and waits for the answer before moving on.
    /// If location is off, stays here so picking a city is the next step.
    private func askForLocation() {
        guard !isAsking else { return }
        isAsking = true
        model.useCurrentLocation()
        Task {
            for _ in 0..<300 where model.location.authorization == .notDetermined {
                try? await Task.sleep(for: .milliseconds(200))
            }
            isAsking = false
            if model.location.isDenied {
                locationDenied = true
            } else {
                afterLocation()
            }
        }
    }

    /// Location answered: on to alerts, unless they've already been asked.
    private func afterLocation() {
        Task {
            await refreshNotificationStatus()
            if notificationStatus != .notDetermined { finish() }
        }
    }

    private func askForAlerts() {
        askedNotifications = true
        Task {
            await PushTokens.requestGroupAlerts()
            await refreshNotificationStatus()
            finish()
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Land on Spin, with a hint pointing at the button (the full tour only).
    private func finish() {
        UserDefaults.standard.set(true, forKey: TourPage.seenNewKey)
        // The full tour, counted once per device (a replay from Settings doesn't count again).
        if pages.contains(.welcome) && !UserDefaults.standard.bool(forKey: "stats.tourCounted") {
            UserDefaults.standard.set(true, forKey: "stats.tourCounted")
            UsageStats.record(skippedTour ? .tourSkipped : .tourFinished)
        }
        if pages.contains(.welcome) {
            model.selectedTab = .spin
            Hint.spinFirst.show()
        }
        onFinish()
    }
}

extension TourPage {
    /// The "New in 1.1" card on the Group tab was seen (or the tour was).
    static let seenNewKey = "tour.seenNew11"
}

/// "Where to eat? Let the *table* decide." — with a hand-drawn saffron
/// underline under "table" that draws itself in.
private struct WelcomeTitle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Where to eat?")
                .foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Let the ")
                Text("table")
                    .overlay(alignment: .bottom) {
                        Swoosh()
                            .trim(from: 0, to: drawn)
                            .stroke(Theme.saffron, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                            .frame(height: 12)
                            .padding(.horizontal, -4)
                            .offset(y: 10)
                    }
                Text(" decide.")
            }
        }
        .font(Theme.display(32))
        .foregroundStyle(Theme.text)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Where to eat? Let the table decide.")
        .accessibilityAddTraits(.isHeader)
        .task {
            if reduceMotion { drawn = 1; return }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.6)) { drawn = 1 }
        }
    }
}

/// A loose, slightly tilted brush stroke, like an underline drawn by hand.
private struct Swoosh: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.15))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2),
                      control1: CGPoint(x: rect.width * 0.3, y: rect.maxY),
                      control2: CGPoint(x: rect.width * 0.7, y: rect.midY))
        return path
    }
}

/// The ForkRoad mark: the app icon (Design/AppIcon.svg), with icon-style corners.
struct ForkMark: View {
    var body: some View {
        GeometryReader { geo in
            Image("ForkRoadLogo")
                .resizable()
                .interpolation(.high)
                .clipShape(RoundedRectangle(cornerRadius: min(geo.size.width, geo.size.height) * 0.225,
                                            style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Tablewhere logo")
    }
}
