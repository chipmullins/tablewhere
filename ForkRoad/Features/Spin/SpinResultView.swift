import SwiftUI
import MapKit
import PickerCore

/// The pick, full screen (1.2): a saffron header with the name in big type
/// ("THE WHEEL PICKED"), icon-only actions, one primary "Let's go · N min
/// drive", "Make it a group plan", and "Not tonight · spin again".
/// Eat in shows the meal, its note and its recipe instead.
struct SpinResultView: View {
    let result: SpinResult
    /// Home meals' notes, by reel ID.
    var notes: [String: String] = [:]
    var onClose: () -> Void
    var onNotTonight: () -> Void
    var onSpinAgain: () -> Void
    var onBlacklist: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showDetail = false
    @State private var driveMinutes: Int?
    /// The home result, while it's being swiped away.
    @State private var dragX: CGFloat = 0
    @State private var refresh = 0
    @State private var appeared = false
    /// The result zooms into the details (iOS 18+).
    @Namespace private var zoom

    private var place: Place { result.place }
    private var actions: ListActions { ListActions(context: context) }
    /// Something you typed onto your wheel ("Leftovers") isn't a real place.
    private var isTyped: Bool { place.id.hasPrefix("typed|") }

    var body: some View {
        GeometryReader { geo in
            let headerHeight = max(300, min(380, geo.size.height * 0.44)) + geo.safeAreaInsets.top
            ScrollView {
                VStack(spacing: 0) {
                    header(topInset: geo.safeAreaInsets.top)
                        .frame(height: headerHeight)
                    actionsSheet(minHeight: geo.size.height - headerHeight + geo.safeAreaInsets.top + 32)
                        .padding(.top, -32)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .background(Theme.night)
        .navigationDestination(isPresented: $showDetail) {
            PlaceDetailView(place: place).zoomDestination(id: place.id, ns: zoom)
        }
        .task(id: place.id) { await loadDriveTime() }
        .sensoryFeedback(Haptic.tick, trigger: refresh)
        .onAppear { withAnimation(reduceMotion ? nil : Motion.reveal) { appeared = true } }
        .accessibilityAction(named: "Spin again", onSpinAgain)
        .accessibilityAction(named: "Back to Spin", onClose)
    }

    // MARK: Header

    private func header(topInset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Theme.saffron
            // A faint map of where it is, under the saffron.
            if !result.isHome && !isTyped {
                Map(initialPosition: .region(MKCoordinateRegion(center: place.coordinate,
                                                                latitudinalMeters: 1600,
                                                                longitudinalMeters: 1600)),
                    interactionModes: [])
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .opacity(0.18)
                    .saturation(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(result.isHome ? "TONIGHT YOU’RE MAKING" : "THE WHEEL PICKED", systemImage: "sparkles")
                        .font(Theme.body(12, .bold))
                        .tracking(1.8)
                        .foregroundStyle(Theme.onSaffron)
                        .accessibilityLabel(result.isHome ? "Tonight you’re making" : "The wheel picked")
                    Spacer()
                    if !result.isHome && !isTyped {
                        SharePickButton(place: place, context: .spin) {
                            RoundIconLabel(systemImage: "square.and.arrow.up", background: .white.opacity(0.6), bordered: false)
                        }
                        .accessibilityLabel("Share your pick")
                    }
                    RoundIconButton(label: "Back to Spin", systemImage: "xmark",
                                    background: .white.opacity(0.6), bordered: false, action: onClose)
                }
                .padding(.top, topInset + 8)

                Spacer(minLength: 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text(place.name)
                        .font(.custom("Outfit-ExtraBold", size: 52, relativeTo: .largeTitle))
                        .tracking(-2)
                        .lineSpacing(-6)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(Theme.onSaffron)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("Your pick: \(place.name)")
                    Text(subtitle)
                        .font(Theme.body(15, .medium))
                        .foregroundStyle(Theme.onSaffron)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .offset(x: dragX)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .zoomSource(id: place.id, ns: zoom)
                .contentShape(Rectangle())
                .onTapGesture { if !result.isHome && !isTyped { showDetail = true } }
                .accessibilityAddTraits(!result.isHome && !isTyped ? .isButton : [])
                .accessibilityHint(!result.isHome && !isTyped ? "Shows details" : "")
                .simultaneousGesture(swipe, including: result.isHome ? .all : .subviews)
                .padding(.bottom, 56)
            }
            .padding(.horizontal, 24)
        }
        .overlay(alignment: .trailing) {
            // What a swipe will do, showing as you drag (Eat in).
            if dragX < -24 {
                Label("Not tonight", systemImage: "arrow.uturn.right")
                    .font(Theme.body(13, .bold))
                    .foregroundStyle(Theme.onSaffron)
                    .padding(.trailing, 20)
                    .opacity(min(1, Double(-dragX - 24) / 60))
            }
        }
        .clipped()
    }

    private var subtitle: String {
        if result.isHome {
            let note = notes[place.id] ?? ""
            return note.isEmpty ? "Picked from \(plural(result.spunFrom, "meal"))" : note
        }
        if isTyped { return "From your wheel · picked from \(result.spunFrom)" }
        return "\(place.category) · \(place.distanceLabel) · picked from \(plural(result.spunFrom, "place"))"
    }

    /// Eat in: swipe the meal left for "Not tonight" (missing an ingredient).
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                // Left only, and mostly sideways (so scrolling still works).
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragX = min(0, value.translation.width)
            }
            .onEnded { _ in
                let skip = dragX < -100
                withAnimation(.snappy) { dragX = 0 }
                if skip { onNotTonight() }
            }
    }

    // MARK: Body

    private func actionsSheet(minHeight: CGFloat) -> some View {
        VStack(spacing: 22) {
            if result.isHome {
                homeActions
            } else if isTyped {
                Button("Spin again", action: onSpinAgain)
                    .buttonStyle(.sleekPrimary)
            } else {
                placeActions
            }

            Button(action: onNotTonight) {
                Text(result.isHome ? "Missing something? Not tonight · spin again" : "Not tonight · spin again")
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .underline(true, pattern: .solid)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.pressable)
            .accessibilityHint(result.isHome ? "Leaves it out for tonight, then spins again"
                                             : "Leaves it out of spins for a few hours, then spins again")
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
        .background(Theme.night, in: UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.sheet,
                                                             topTrailingRadius: Theme.Radius.sheet,
                                                             style: .continuous))
    }

    @ViewBuilder
    private var placeActions: some View {
        let _ = refresh
        let onList = actions.list(for: place)
        HStack {
            IconAction(label: "Call", systemImage: "phone") {
                if let url = PlaceLinks.phoneURL(place) { openURL(url) }
            }
            .disabled(place.phoneNumber == nil)
            Spacer(minLength: 8)
            IconAction(label: "Favorite", systemImage: onList == .favorites ? "heart.fill" : "heart",
                       isOn: onList == .favorites, haptic: Haptic.tick) {
                actions.toggle(place, in: .favorites)
                refresh += 1
            }
            Spacer(minLength: 8)
            IconAction(label: "Try later", systemImage: onList == .interested ? "bookmark.fill" : "bookmark",
                       isOn: onList == .interested, haptic: Haptic.tick, hint: "Saves it to your To try list") {
                actions.toggle(place, in: .interested)
                refresh += 1
            }
            Spacer(minLength: 8)
            IconAction(label: "Blacklist", systemImage: "nosign", haptic: Haptic.destructive,
                       hint: "Never show it again. You can undo.", action: onBlacklist)
        }

        Button {
            PlaceLinks.openDirections(place)
            VisitFollowUp.record(place, in: context)
        } label: {
            Label(driveMinutes.map { "Let’s go · \($0) min drive" } ?? "Let’s go", systemImage: "location.north.fill")
        }
        .buttonStyle(.sleekPrimary)
        .accessibilityHint("Opens directions")

        Button { model.startPlan(with: place) } label: {
            SleekRow(systemImage: "person.2", title: "Make it a group plan", subtitle: "Send the link, pick a time")
        }
        .buttonStyle(.pressable)

        Button("See details") { showDetail = true }
            .font(Theme.body(14, .semibold))
            .foregroundStyle(Theme.muted)
            .frame(minHeight: 44)
    }

    @ViewBuilder
    private var homeActions: some View {
        if let url = place.websiteURL {
            Button { openURL(url) } label: {
                Label("Open the recipe", systemImage: "book")
            }
            .buttonStyle(.sleekPrimary)
        }
        Button("Sounds good", action: onClose)
            .buttonStyle(SleekButtonStyle(kind: place.websiteURL == nil ? .ink : .plain, height: place.websiteURL == nil ? 60 : 52))
            .accessibilityHint("Back to Spin")
    }

    /// "4 min drive": from where you are (or your search spot), with traffic.
    private func loadDriveTime() async {
        guard !result.isHome, !isTyped else { return }
        let from = model.location.coordinate ?? model.center
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        request.transportType = .automobile
        request.departureDate = Date()
        if let seconds = try? await MKDirections(request: request).calculateETA().expectedTravelTime {
            driveMinutes = max(1, Int((seconds / 60).rounded()))
        }
    }
}
