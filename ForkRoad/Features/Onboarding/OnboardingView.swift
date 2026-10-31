import SwiftUI

/// First launch: what ForkRoad is, a quick tour of how it works, then
/// location (or pick a city) and your name. Settings can show it again.
struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var showCityPicker = false
    @State private var name = Identity.displayName ?? ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                ForEach(Array(Self.tour.enumerated()), id: \.offset) { index, stop in
                    tourPage(stop, next: index + 2).tag(index + 1)
                }
                location.tag(locationPage)
                nameStep.tag(namePage)
            }
            .overlay(alignment: .topTrailing) {
                if page >= 1 && page < locationPage {
                    Button("Skip tour") { page = locationPage }
                        .font(Theme.body(15, .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }
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
        .sheet(isPresented: $showCityPicker, onDismiss: { if !model.isUsingCurrentLocation { page = namePage } }) {
            LocationPickerView()
        }
    }

    // MARK: The tour

    struct TourStop {
        let icon: String
        let eyebrow: String
        let title: String
        let points: [TourPoint]
    }

    struct TourPoint: Hashable {
        let icon: String
        let text: String
        init(_ icon: String, _ text: String) { self.icon = icon; self.text = text }
    }

    static let tour: [TourStop] = [
        TourStop(icon: "map.fill", eyebrow: "Discover", title: "See what’s around you",
                 points: [
                    TourPoint("slider.horizontal.3", "Set how far to look, then filter by cuisine, diet, or no fast food."),
                    TourPoint("hand.tap", "Tap the map to open it big, then tap anywhere to search the other side of town."),
                    TourPoint("magnifyingglass", "Search any restaurant or craving by name.")
                 ]),
        TourStop(icon: "dice.fill", eyebrow: "Spin", title: "Can’t decide? Spin.",
                 points: [
                    TourPoint("dice", "Spin from what’s nearby, your Favorites, or places you want to try."),
                    TourPoint("arrow.triangle.2.circlepath", "It won’t repeat places you landed on this week."),
                    TourPoint("pause.circle", "Tired of a place? Leave it out of spins without removing it.")
                 ]),
        TourStop(icon: "heart.fill", eyebrow: "Lists", title: "Keep your places",
                 points: [
                    TourPoint("heart", "Heart places you love, bookmark ones you want to try, and blacklist ones you never want to see."),
                    TourPoint("plus.circle", "Not on Apple Maps? Add it yourself with a name, type, and notes."),
                    TourPoint("mappin.and.ellipse", "Add areas, like a city you’re visiting, to sort your lists by place.")
                 ]),
        TourStop(icon: "person.3.fill", eyebrow: "Group picks", title: "Decide together",
                 points: [
                    TourPoint("checkmark.circle", "Vote: you pick the options, friends suggest one each, and most votes wins."),
                    TourPoint("dice", "Spin: everyone adds one place, then you spin the wheel."),
                    TourPoint("message", "Friends join from iMessage, or a web link if they don’t have ForkRoad."),
                    TourPoint("clock", "Lock it in, set a time, add a note, and send everyone the plan.")
                 ])
    ]

    private var locationPage: Int { Self.tour.count + 1 }
    private var namePage: Int { Self.tour.count + 2 }
    private var pageCount: Int { Self.tour.count + 3 }

    private func tourPage(_ stop: TourStop, next: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 40)
            symbolArt(stop.icon)
            VStack(alignment: .leading, spacing: 6) {
                Text(stop.eyebrow.uppercased())
                    .font(Theme.body(12, .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.accentText)
                Text(stop.title)
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(stop.points, id: \.self) { point in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: point.icon)
                            .font(Theme.body(16, .semibold))
                            .foregroundStyle(Theme.accentText)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        Text(point.text)
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .card(radius: 20)
            Spacer()
            primaryButton(next == locationPage ? "Got it" : "Next") { page = next }
            Color.clear.frame(height: 44)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    // MARK: Pages

    private var welcome: some View {
        stepPage(
            art: AnyView(ForkMark().frame(width: 140, height: 140)),
            title: "Every dinner is a\nfork in the road.",
            text: "Browse what’s nearby, spin when you can’t decide, and pick with friends right in your group chat.",
            primary: ("Show me around", { page = 1 }),
            secondary: nil
        )
    }

    private var location: some View {
        stepPage(
            art: AnyView(symbolArt("location.fill")),
            title: "Find food near you",
            text: "ForkRoad uses your location only while you’re using the app, to find restaurants around you. You can also pick any city instead.",
            primary: ("Use my location", {
                model.useCurrentLocation()
                page = namePage
            }),
            secondary: ("Pick a city instead", { showCityPicker = true })
        )
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            symbolArt("person.2.fill")
            Text("What should friends call you?")
                .font(Theme.display(30))
                .foregroundStyle(Theme.text)
            Text("Your first name shows up when you vote on group picks. You can change it anytime in Settings.")
                .font(Theme.body(16))
                .foregroundStyle(Theme.muted)
            TextField("Your first name", text: $name)
                .font(Theme.body(17, .medium))
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit(finish)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .card(radius: 16)
            Spacer()
            primaryButton("Start exploring", action: finish)
            Button("Skip for now") { finish() }
                .font(Theme.body(15, .semibold))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
            Text("ForkRoad · Created by Chip Mullins")
                .font(Theme.body(12))
                .foregroundStyle(Theme.muted.opacity(0.7))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    // MARK: Building blocks

    private func stepPage(art: AnyView, title: String, text: String,
                      primary: (String, () -> Void), secondary: (String, () -> Void)?) -> some View {
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
            .foregroundStyle(Theme.saffron)
            .frame(width: 84, height: 84)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityHidden(true)
    }

    private func finish() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { Identity.displayName = trimmed }
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
