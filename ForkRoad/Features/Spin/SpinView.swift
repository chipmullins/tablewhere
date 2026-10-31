import SwiftUI
import SwiftData
import PickerCore

/// The randomizer: a slot-machine reel that lands on tonight's pick.
struct SpinView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query private var areas: [SavedArea]

    @State private var reelIndex = 0
    /// Frozen copy of the pool while spinning/landed, so new search results
    /// arriving mid-spin can't change what the reel shows.
    @State private var reelPool: [Place] = []
    @State private var isSpinning = false
    @State private var winner: Place?
    @State private var showDetail = false
    /// Increments each time a spin lands; drives the bounce and burst.
    @State private var landCount = 0
    @State private var showLocationPicker = false
    @State private var showWheelPicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var actions: ListActions { ListActions(context: context) }

    private var rules: Randomizer.Rules {
        model.rules(
            blockedPlaces: blockedPlaces,
            blockedCategories: blockedCategories,
            recent: actions.recentPlaceIDs(),
            // Saved places are the user's own picks, so the radius doesn't apply to them.
            maxDistance: model.spinSource == .nearby ? model.radiusMeters : nil
        )
    }

    /// Everything that could come up on the reel.
    private var pool: [Place] {
        let source: [Place]
        switch model.spinSource {
        case .nearby: source = model.places
        // You chose these on purpose, so blacklist/repeat rules don't apply.
        case .picked: return model.pickedWheel
        case .favorites, .interested:
            let list = model.spinSource.savedList
            source = saved.filter { $0.list == list && !$0.skipInSpins }
                .filtered(by: model.listCity, near: model.center, areas: areas)
                .map { $0.asPlace(from: model.center) }
        }
        return Randomizer.eligible(source, rules: rules)
    }

    var body: some View {
        @Bindable var model = model
        let pool = self.pool
        // Copied out so the animation closure (which can run off the main
        // actor) doesn't reach back into the view.
        let reduceMotion = self.reduceMotion
        let shown = (isSpinning || winner != nil) ? reelPool : pool

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Can’t decide?\nWe got you.")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)

                Picker("Pick from", selection: $model.spinSource) {
                    ForEach(SpinSource.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: model.spinSource) { reset() }
                .onChange(of: model.listCity) { reset() }

                if model.spinSource == .nearby {
                    // Where and how far, right here (same settings as Discover).
                    HStack(spacing: 8) {
                        Button { showLocationPicker = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: model.isUsingCurrentLocation ? "location.fill" : "mappin")
                                    .foregroundStyle(Theme.accentText)
                                Text(model.locationName).lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(Theme.body(11, .bold))
                                    .foregroundStyle(Theme.muted)
                            }
                            .font(Theme.body(14, .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.hairline))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Spinning near \(model.locationName). Change location")

                        Menu {
                            Picker("Search radius", selection: $model.radiusMiles) {
                                ForEach([0.5, 1, 2, 3, 5, 10], id: \.self) { miles in
                                    Text(RadiusSlider.label(miles)).tag(miles)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "circle.dashed").foregroundStyle(Theme.accentText)
                                Text(model.radiusLabel)
                                Image(systemName: "chevron.down")
                                    .font(Theme.body(11, .bold))
                                    .foregroundStyle(Theme.muted)
                            }
                            .font(Theme.body(14, .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.hairline))
                        }
                        .accessibilityLabel("Search radius, \(model.radiusLabel)")
                        Spacer(minLength: 0)
                    }
                    .sheet(isPresented: $showLocationPicker) { LocationPickerView() }
                    .onChange(of: model.center.latitude) { reset() }
                    .onChange(of: model.radiusMiles) { reset() }

                    CuisineChips(selection: $model.cuisines, diet: $model.diet)
                } else if model.spinSource == .picked {
                    PickedWheelEditor(showPicker: $showWheelPicker)
                        .onChange(of: model.pickedWheel.map(\.id)) { reset() }
                        .sheet(isPresented: $showWheelPicker) { WheelPickerSheet() }
                } else {
                    HStack(spacing: 8) {
                        CityMenu(metros: saved.filter { $0.list == model.spinSource.savedList }.metros)
                        NoFastFoodChip()
                    }
                }

                rulesSummary(count: pool.count)

                reel(shown)
                    .keyframeAnimator(initialValue: 1.0, trigger: landCount) { content, scale in
                        content.scaleEffect(reduceMotion ? 1 : scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.06, duration: 0.18, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                    }
                    .overlay { LandingBurst(trigger: landCount).allowsHitTesting(false) }

                HStack {
                    Spacer()
                    spinButton(pool)
                    Spacer()
                }

                if let winner, !isSpinning {
                    resultCard(winner)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .modifier(active: FlipIn(angle: -70, opacity: 0),
                                                 identity: FlipIn(angle: 0, opacity: 1)),
                            removal: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.spring(duration: 0.55, bounce: 0.35), value: winner)
        }
        .background(Theme.night)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showDetail) {
            if let winner { PlaceDetailView(place: winner) }
        }
        .sensoryFeedback(.selection, trigger: reelIndex)
        .sensoryFeedback(.success, trigger: winner)
    }

    // MARK: Pieces

    private func rulesSummary(count: Int) -> some View {
        let picked = model.spinSource == .picked
        let parts: [String?] = picked ? ["Your hand-picked wheel", "\(count) in the wheel"] : [
            model.spinSource == .nearby ? "Within \(model.radiusLabel)"
                : (model.spinSource == .favorites ? "From your favorites" : "Places you want to try"),
            model.spinSource != .nearby ? areaChip : nil,
            skippedCount > 0 ? "Skipping \(skippedCount) you left out" : nil,
            model.spinSource == .nearby && !model.cuisines.isEmpty ? model.cuisineSummary : nil,
            "\(count) in the wheel",
            blockedPlaces.isEmpty && blockedCategories.isEmpty ? nil : "Skips \(blockedPlaces.count + blockedCategories.count) blacklisted",
            model.excludeFastFood ? "No fast food" : nil,
            "No repeats this week"
        ]
        let labels = parts.compactMap { $0 }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(labels, id: \.self) { part in
                    Text(part)
                        .font(Theme.body(12, .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surface, in: Capsule())
                }
            }
        }
    }

    private func reel(_ pool: [Place]) -> some View {
        let count = pool.count
        let current = count > 0 ? pool[reelIndex % count] : nil
        let previous = count > 1 ? pool[(reelIndex - 1 + count) % count].name : " "
        let next = count > 1 ? pool[(reelIndex + 1) % count].name : " "
        let landed = winner != nil && !isSpinning

        return VStack(spacing: 14) {
            Text(previous).font(Theme.body(17, .semibold)).foregroundStyle(Theme.muted.opacity(0.35))
            HStack(spacing: 12) {
                if let current {
                    MonogramTile(name: current.name, category: current.category, size: 40)
                    Text(current.name)
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(emptyReelText)
                        .font(Theme.display(20))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .padding(.horizontal, 14)
            .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(landed ? Theme.saffron : Theme.hairline, lineWidth: 1.5)
            )
            .padding(.horizontal, 14)
            Text(next).font(Theme.body(17, .semibold)).foregroundStyle(Theme.muted.opacity(0.35))
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .card(radius: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current.map { "Reel showing \($0.name)" } ?? "Reel is empty")
    }

    /// Saved places on the current list (and area) that are left out of spins.
    private var skippedCount: Int {
        guard let list = model.spinSource.savedList else { return 0 }
        return saved.filter { $0.list == list && $0.skipInSpins }
            .filtered(by: model.listCity, near: model.center, areas: areas).count
    }

    private var areaChip: String {
        let metros = saved.filter { $0.list == model.spinSource.savedList }.metros
        switch model.listCity {
        case .all: return "All areas"
        case .metro(let name): return "In \(metros.first { $0.name == name }?.label ?? name)"
        case .area(let name): return "In \(name)"
        case .here:
            let label = metros.first { $0.contains(model.center) }?.label ?? model.currentCity
            return label.map { "In \($0)" } ?? "Around here"
        }
    }

    private var emptyReelText: String {
        switch model.spinSource {
        case .nearby: return "No places in range"
        case .picked: return "Add a few places to your wheel"
        case .favorites:
            return model.listCity == .all ? "Heart some favorites first" : "No favorites around here yet"
        case .interested:
            return model.listCity == .all ? "Bookmark places to try first" : "Nothing saved around here yet"
        }
    }

    private func spinButton(_ pool: [Place]) -> some View {
        Button { spin(pool) } label: {
            Text(isSpinning ? "…" : (winner == nil ? "Spin" : "Again"))
                .font(Theme.display(20))
                .foregroundStyle(Theme.onSaffron)
                .frame(width: 104, height: 104)
                .background(Theme.saffron, in: Circle())
                .overlay(Circle().strokeBorder(Theme.saffron.opacity(0.25), lineWidth: 6))
                .shadow(color: Theme.saffron.opacity(0.28), radius: 20, y: 12)
        }
        .buttonStyle(.plain)
        .disabled(isSpinning || pool.isEmpty)
        .opacity(pool.isEmpty ? 0.4 : 1)
        .accessibilityLabel("Spin")
    }

    private func resultCard(_ place: Place) -> some View {
        // Something you typed onto your wheel ("Leftovers") isn't a real place.
        let isTyped = place.id.hasPrefix("typed|")
        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Tonight’s pick", color: Theme.accentText)
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).font(Theme.display(24)).foregroundStyle(Theme.text)
                Text(isTyped ? "From your wheel" : "\(place.category) · \(place.distanceLabel)")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.muted)
            }
            if !isTyped { resultActions(place) }
        }
        .padding(18)
        .card(radius: 24)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.saffron.opacity(0.35)))
    }

    @ViewBuilder
    private func resultActions(_ place: Place) -> some View {
            HStack(spacing: 8) {
                ActionTile(title: "Call", systemImage: "phone") {
                    if let url = PlaceLinks.phoneURL(place) { openURL(url) }
                }
                .disabled(place.phoneNumber == nil)
                ActionTile(title: "Go", systemImage: "location.north.line") {
                    PlaceLinks.openDirections(place)
                    VisitFollowUp.record(place, in: context)
                }
                let onList = actions.list(for: place)
                ActionTile(title: "Favorite",
                           systemImage: onList == .favorites ? "heart.fill" : "heart",
                           tint: onList == .favorites ? Theme.accentText : Theme.text) {
                    actions.toggle(place, in: .favorites)
                }
                ActionTile(title: "Try",
                           systemImage: onList == .interested ? "bookmark.fill" : "bookmark",
                           tint: onList == .interested ? Theme.accentText : Theme.text) {
                    actions.toggle(place, in: .interested)
                }
                ActionTile(title: "Nope", systemImage: "nosign") {
                    actions.block(place)
                    if model.spinSource == .picked { model.togglePicked(place) }
                    winner = nil
                }
            }
            Button("See details") { showDetail = true }
                .font(Theme.body(15, .bold))
                .foregroundStyle(Theme.night)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.text, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .buttonStyle(.plain)
    }

    // MARK: Logic

    /// Decide the winner up front, then animate the reel slowing down onto it.
    private func spin(_ pool: [Place]) {
        guard !isSpinning,
              let pick = Randomizer.pick(from: pool, rules: rules),
              let target = pool.firstIndex(of: pick) else { return }
        reelPool = pool
        isSpinning = true
        winner = nil

        // Start the reel exactly `steps` positions before the winner, so it
        // lands on it naturally instead of jumping at the end. (The start
        // position change isn't noticeable because the reel begins fast.)
        let count = pool.count
        let steps = 22 + Int.random(in: 0...6)
        reelIndex = ((target - steps) % count + count) % count

        Task { @MainActor in
            var delay = 0.03
            let growth = pow(0.28 / 0.03, 1.0 / Double(steps))  // ease out to ~0.28s per step
            for _ in 0..<steps {
                try? await Task.sleep(for: .seconds(delay))
                reelIndex = (reelIndex + 1) % count
                delay *= growth
            }
            reelIndex = target
            winner = pick
            landCount += 1
            isSpinning = false
            if !pick.id.hasPrefix("typed|") { actions.recordSpin(pick) }
            UsageStats.record(.spins)
        }
    }

    private func reset() {
        guard !isSpinning else { return }
        reelIndex = 0
        winner = nil
        reelPool = []
    }
}

/// The result card flips up into place.
private struct FlipIn: ViewModifier {
    let angle: Double
    let opacity: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
            .opacity(opacity)
    }
}

/// A quick saffron burst from the reel when a spin lands.
private struct LandingBurst: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    private let duration: TimeInterval = 0.8

    var body: some View {
        TimelineView(.animation(paused: startedAt == nil)) { timeline in
            Canvas { context, size in
                guard let startedAt else { return }
                let t = timeline.date.timeIntervalSince(startedAt) / duration
                guard t < 1 else { return }
                let progress = CGFloat(1 - pow(1 - t, 3))  // ease out
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let count = 18
                for i in 0..<count {
                    let angle = Double(i) / Double(count) * 2 * .pi + Double(i % 3) * 0.17
                    let distance = (60 + CGFloat(i % 4) * 22) * progress + 30
                    let point = CGPoint(x: center.x + cos(angle) * distance * 1.6,
                                        y: center.y + sin(angle) * distance * 0.8)
                    let radius = (i % 3 == 0 ? 5.0 : 3.5) * (1 - progress * 0.6)
                    let color = i % 4 == 0 ? Color.white : Color(hex: 0xFFB23F)
                    context.opacity = Double(1 - progress)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                        width: radius * 2, height: radius * 2)),
                                 with: .color(color))
                }
            }
        }
        .onChange(of: trigger) {
            guard !reduceMotion else { return }
            startedAt = .now
            Task {
                try? await Task.sleep(for: .seconds(duration))
                startedAt = nil
            }
        }
        .accessibilityHidden(true)
    }
}
