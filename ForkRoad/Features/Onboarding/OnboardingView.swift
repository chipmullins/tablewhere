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

/// The ForkRoad mark (fork whose tines split like roads), drawn in SwiftUI.
struct ForkMark: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 200
            func line(_ build: (inout Path) -> Void, width: CGFloat, color: Color, dash: [CGFloat] = []) {
                var path = Path()
                build(&path)
                let transform = CGAffineTransform(translationX: 20 * s, y: 12 * s).scaledBy(x: 0.8 * s, y: 0.8 * s)
                context.stroke(path.applying(transform), with: .color(color),
                               style: StrokeStyle(lineWidth: width * s * 0.8, lineCap: .round, dash: dash.map { $0 * s * 0.8 }))
            }
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 45 * s),
                         with: .color(Color(hex: 0x0B0B0F)))
            let saffron = Color(hex: 0xFFB23F), ink = Color(hex: 0x1B1306)
            line({ $0.move(to: CGPoint(x: 100, y: 122)); $0.addLine(to: CGPoint(x: 100, y: 178)) }, width: 30, color: saffron)
            line({ $0.move(to: CGPoint(x: 100, y: 124)); $0.addLine(to: CGPoint(x: 100, y: 40)) }, width: 24, color: saffron)
            line({ $0.move(to: CGPoint(x: 100, y: 124))
                   $0.addCurve(to: CGPoint(x: 60, y: 48), control1: CGPoint(x: 100, y: 96), control2: CGPoint(x: 60, y: 88)) },
                 width: 24, color: saffron)
            line({ $0.move(to: CGPoint(x: 100, y: 124))
                   $0.addCurve(to: CGPoint(x: 140, y: 48), control1: CGPoint(x: 100, y: 96), control2: CGPoint(x: 140, y: 88)) },
                 width: 24, color: saffron)
            line({ $0.move(to: CGPoint(x: 100, y: 172)); $0.addLine(to: CGPoint(x: 100, y: 128)) }, width: 3.5, color: ink, dash: [7, 8])
            line({ $0.move(to: CGPoint(x: 100, y: 112)); $0.addLine(to: CGPoint(x: 100, y: 46)) }, width: 3, color: ink, dash: [6, 7])
        }
        .accessibilityLabel("ForkRoad logo")
    }
}
