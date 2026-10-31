import SwiftUI

/// First launch, kept short: what ForkRoad is, then location (or pick a city).
/// Then you land on Spin with a hint to try it. Everything else is taught by
/// one-time hints right where each feature lives (see `Hint`), and your name
/// is asked only when you first start or join a group pick.
/// Settings can show this again.
struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var showCityPicker = false
    @State private var locationDenied = false
    @State private var isAsking = false

    private let pageCount = 2

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                location.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)

            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.saffron : Theme.track)
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .animation(.snappy, value: page)
            .padding(.bottom, 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(page + 1) of \(pageCount)")
        }
        .background(Theme.night.ignoresSafeArea())
        .sheet(isPresented: $showCityPicker, onDismiss: {
            // Picked a city (or "Current location" in the picker): done. Backed out: stay here.
            if model.hasLocation { finish() }
        }) {
            LocationPickerView()
        }
    }

    // MARK: Pages

    private var welcome: some View {
        stepPage(
            art: AnyView(ForkMark().frame(width: 140, height: 140)),
            title: "Every dinner is a\nfork in the road.",
            text: "Browse what’s nearby, spin when you can’t decide, and pick with friends right in your group chat.",
            primary: ("Get started", { page = 1 }),
            secondary: nil,
            footer: AnyView(
                Text("ForkRoad · Created by Chip Mullins")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted.opacity(0.7))
                    .frame(maxWidth: .infinity)
            )
        )
    }

    private var location: some View {
        stepPage(
            art: AnyView(symbolArt("location.fill")),
            title: locationDenied ? "No problem" : "Find food near you",
            text: locationDenied
                ? "Location is off, so pick a city or neighborhood to search instead. You can turn location on later in Settings."
                : "ForkRoad uses your location only while you’re using the app, to find restaurants around you and work out when to leave for group plans. You can also pick any city instead.",
            primary: locationDenied
                ? ("Pick a city", { showCityPicker = true })
                : (isAsking ? "One sec…" : "Use my location", askForLocation),
            secondary: locationDenied ? nil : ("Pick a city instead", { showCityPicker = true }),
            footer: AnyView(
                Text("ForkRoad counts anonymous daily totals (like spins) to get better. Turn it off anytime in Settings.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            )
        )
    }

    // MARK: Building blocks

    private func stepPage(art: AnyView, title: String, text: String,
                          primary: (String, () -> Void), secondary: (String, () -> Void)?,
                          footer: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            art
            Text(title)
                .font(Theme.display(32))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(text)
                .font(Theme.body(16))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            primaryButton(primary.0, action: primary.1)
            if let secondary {
                Button(secondary.0, action: secondary.1)
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                Color.clear.frame(height: 44)
            }
            footer
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.display(18))
                .foregroundStyle(Theme.onSaffron)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func symbolArt(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(Theme.accentText)
            .frame(width: 84, height: 84)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityHidden(true)
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
                finish()
            }
        }
    }

    /// Land on Spin, with a hint pointing at the button.
    private func finish() {
        model.selectedTab = .spin
        Hint.spinFirst.show()
        onFinish()
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
        .accessibilityLabel("ForkRoad logo")
    }
}
