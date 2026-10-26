import SwiftUI

/// First launch: what ForkRoad is, location (or pick a city), and your name.
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
                location.tag(1)
                nameStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)

            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index == page ? Theme.saffron : Theme.track)
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .animation(.snappy, value: page)
            .padding(.bottom, 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(page + 1) of 3")
        }
        .background(Theme.night.ignoresSafeArea())
        .sheet(isPresented: $showCityPicker, onDismiss: { if !model.isUsingCurrentLocation { page = 2 } }) {
            LocationPickerView()
        }
    }

    // MARK: Pages

    private var welcome: some View {
        stepPage(
            art: AnyView(ForkMark().frame(width: 140, height: 140)),
            title: "Every dinner is a\nfork in the road.",
            text: "Browse what’s nearby, spin when you can’t decide, and pick with friends right in your group chat.",
            primary: ("Let’s go", { page = 1 }),
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
                page = 2
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
