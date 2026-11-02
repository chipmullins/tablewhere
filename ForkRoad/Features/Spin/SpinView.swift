import SwiftUI
import SwiftData
import PickerCore

/// The randomizer: a slot-machine reel that lands on your pick.
struct SpinView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query private var areas: [SavedArea]
    @Query(sort: \HomeRecipe.name) private var recipes: [HomeRecipe]

    @State private var showFilters = false
    @State private var showAddRecipe = false
    @State private var showWheelPicker = false
    /// The full-screen reveal (same as Group Spin) while it plays.
    @State private var reveal: SpinRevealRequest?

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
        // Eat in: your home meals (minus tonight's "Not tonight"s).
        if model.eatIn {
            let skipped = model.skippedForNowIDs
            return recipes.map(\.asSpinItem).filter { !skipped.contains($0.id) }
        }
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
        // "Not tonight" places sit out for a few hours.
        let skipped = model.skippedForNowIDs
        return Randomizer.eligible(source, rules: rules).filter { !skipped.contains($0.id) }
    }

    var body: some View {
        @Bindable var model = model
        let pool = self.pool

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Can’t decide?\nWe got you.")
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)

                Picker("Eat out or in", selection: $model.eatIn.animation(.snappy)) {
                    Text("Eat out").tag(false)
                    Text("Eat in").tag(true)
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(Haptic.tick, trigger: model.eatIn)

                if model.eatIn {
                    eatInHeader
                } else {
                    eatOutControls
                }

                // The reel, Spin button, and result live in their own view, so
                // each reel tick redraws only them (not the lists and filters above).
                SpinStage(pool: pool,
                          resetKey: resetKey,
                          emptyText: emptyReelText,
                          footnote: footnote(count: pool.count),
                          isPickedWheel: !model.eatIn && model.spinSource == .picked,
                          isHome: model.eatIn,
                          notes: recipeNotes,
                          rulesAtSpin: { rules },
                          reveal: $reveal)

                if !model.eatIn {
                    HintCard(.spinFirst)
                    HintCard(.myWheel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.night)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if let reveal {
                SpinReveal(names: reveal.names, winner: reveal.winner) { self.reveal = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: reveal?.id)
        .onChange(of: model.spinSource) {
            if model.spinSource == .picked { Hint.myWheel.dismiss() }
        }
        .sheet(isPresented: $showAddRecipe) { RecipeForm() }
    }

    /// Eat out: where to pick from, and that source's filters.
    @ViewBuilder
    private var eatOutControls: some View {
        @Bindable var model = model
        Picker("Pick from", selection: $model.spinSource) {
            ForEach(SpinSource.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)

        // One row instead of a block of chips: the Spin button stays on screen.
        switch model.spinSource {
                case .nearby:
                    Button { showFilters = true } label: {
                        FilterRow(icon: model.isUsingCurrentLocation ? "location.fill" : "mappin",
                                  title: model.locationName,
                                  detail: nearbyFilterDetail)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filters: \(model.locationName), \(nearbyFilterDetail)")
                    .accessibilityHint("Change where, how far, and what kind of food")
                    .sheet(isPresented: $showFilters) { SpinFiltersSheet() }
                case .picked:
                    PickedWheelEditor(showPicker: $showWheelPicker)
                        .sheet(isPresented: $showWheelPicker) { WheelPickerSheet() }
                case .favorites, .interested:
                    HStack(spacing: 8) {
                        CityMenu(metros: saved.filter { $0.list == model.spinSource.savedList }.metros)
                        NoFastFoodChip()
                    }
                }
    }

    /// Eat in: how many meals, and a quick way to add one.
    @ViewBuilder
    private var eatInHeader: some View {
        if recipes.isEmpty {
            EmptyState(
                art: .plate,
                title: "What do you make at home?",
                message: "Add a few go-to meals, like tacos or spaghetti. Then spin to pick tonight’s.",
                primary: ("Add a meal", { showAddRecipe = true })
            )
            .padding(.vertical, 8)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "frying.pan")
                    .foregroundStyle(Theme.accentText)
                Text("\(recipes.count) home meal\(recipes.count == 1 ? "" : "s")")
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button { showAddRecipe = true } label: {
                    Label("Add", systemImage: "plus")
                        .font(Theme.body(14, .bold))
                        .foregroundStyle(Theme.accentText)
                }
                .buttonStyle(.plain)
                Button("Edit") {
                    model.showHomeList = true
                    model.selectedTab = .lists
                }
                .font(Theme.body(14, .bold))
                .foregroundStyle(Theme.accentText)
                .buttonStyle(.plain)
                .accessibilityHint("Opens your Home list in Lists")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// Recipe notes by reel ID, for the result card.
    private var recipeNotes: [String: String] {
        Dictionary(recipes.map { ($0.asSpinItem.id, $0.note) }, uniquingKeysWith: { first, _ in first })
    }

    /// When any of these change, the reel starts over.
    private var resetKey: String {
        [model.eatIn ? "in" : "out", model.spinSource.rawValue, "\(model.listCity)", "\(model.center.latitude),\(model.center.longitude)",
         "\(model.radiusMiles)", model.pickedWheel.map(\.id).joined(separator: ",")].joined(separator: "|")
    }

    // MARK: Pieces

    /// "2 mi · All cuisines · No fast food", under the location in the filter row.
    private var nearbyFilterDetail: String {
        var parts = [model.radiusLabel,
                     model.cuisines.isEmpty ? "All cuisines" : model.cuisineSummary]
        if model.diet != .none { parts.append(model.diet.label) }
        if model.excludeFastFood { parts.append("No fast food") }
        return parts.joined(separator: " · ")
    }

    /// One quiet line under the Spin button.
    private func footnote(count: Int) -> String {
        if model.eatIn {
            let skipped = recipes.count - count
            return skipped > 0 ? "\(count) meal\(count == 1 ? "" : "s") · \(skipped) not tonight"
                               : "\(count) meal\(count == 1 ? "" : "s")"
        }
        if model.spinSource == .picked { return count < 2 ? "Add at least 2 to spin" : "\(count) on your wheel" }
        var parts = ["\(count) \(count == 1 ? "place" : "places")"]
        if model.spinSource != .nearby { parts.append(areaChip) }
        if skippedCount > 0 { parts.append("\(skippedCount) left out") }
        parts.append("favors ones you haven’t spun lately")
        return parts.joined(separator: " · ")
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
        if model.eatIn { return recipes.isEmpty ? "Add a few meals first" : "Nothing left for tonight" }
        switch model.spinSource {
        case .nearby: return model.hasLocation ? "No places in range" : "Pick a location above"
        case .picked: return "Add a few places to your wheel"
        case .favorites:
            return model.listCity == .all ? "Heart some favorites first" : "No favorites around here yet"
        case .interested:
            return model.listCity == .all ? "Bookmark places to try first" : "Nothing saved around here yet"
        }
    }
}

/// The reel, the Spin button, and the result card. Owns the spin state so a
/// reel tick only redraws this view.
/// Asks SpinView to play the full-screen reveal for a spin.
struct SpinRevealRequest: Identifiable, Equatable {
    let id = UUID()
    let names: [String]
    let winner: String
}

private struct SpinStage: View {
    let pool: [Place]
    let resetKey: String
    let emptyText: String
    /// "165 places · skips ones you had this week", under the button.
    let footnote: String
    /// Your own wheel spins exactly what you chose (no rules at spin time).
    let isPickedWheel: Bool
    /// Eat in: the reel holds home meals (see HomeRecipe.asSpinItem).
    var isHome = false
    /// Home meals' notes, by reel ID.
    var notes: [String: String] = [:]
    /// The rules for picking, worked out once when you tap Spin.
    let rulesAtSpin: () -> Randomizer.Rules

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var reelIndex = 0
    /// Frozen copy of the pool while spinning/landed, so new search results
    /// arriving mid-spin can't change what the reel shows.
    @State private var reelPool: [Place] = []
    @State private var isSpinning = false
    @State private var winner: Place?
    @State private var showDetail = false
    /// Increments each time a spin lands; drives the bounce and burst.
    @State private var landCount = 0
    @State private var message: String?
    @Binding var reveal: SpinRevealRequest?
    /// Settings → "Full-screen spin". On: the Group Spin reveal. Off: just the reel.
    @AppStorage("spinReveal") private var useReveal = true
    /// The pick waiting for the reveal to finish.
    @State private var pending: (place: Place, index: Int)?
    /// The home result card, while it's being swiped away.
    @State private var dragX: CGFloat = 0
    /// The result card zooms into the details (iOS 18+).
    @Namespace private var zoom

    private var actions: ListActions { ListActions(context: context) }
    private var emptyReelText: String { emptyText }
    private var minimumToSpin: Int { isPickedWheel ? 2 : 1 }

    var body: some View {
        // Copied out so the animation closure (which can run off the main
        // actor) doesn't reach back into the view.
        let reduceMotion = self.reduceMotion
        let shown = (isSpinning || winner != nil) ? reelPool : pool

        VStack(alignment: .leading, spacing: 18) {
            // An empty Custom wheel already shows its "Build your own wheel" card.
            if !(isPickedWheel && shown.isEmpty) {
            reel(shown)
                .keyframeAnimator(initialValue: 1.0, trigger: landCount) { content, scale in
                    content.scaleEffect(reduceMotion ? 1 : scale)
                } keyframes: { _ in
                    SpringKeyframe(1.06, duration: 0.18, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                }
                .overlay { LandingBurst(trigger: landCount).allowsHitTesting(false) }
            }

            HStack {
                Spacer()
                spinButton(pool)
                Spacer()
            }

            if winner == nil && message == nil && (!pool.isEmpty || isPickedWheel) {
                Text(footnote)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if let message {
                Text(message)
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

            if let winner, !isSpinning {
                Group {
                    if isHome { homeResultCard(winner) } else { resultCard(winner) }
                }
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .modifier(active: FlipIn(angle: -70, opacity: 0),
                                             identity: FlipIn(angle: 0, opacity: 1)),
                        removal: .opacity))
            }
        }
        .animation(.spring(duration: 0.55, bounce: 0.35), value: winner)
        .navigationDestination(isPresented: $showDetail) {
            if let winner { PlaceDetailView(place: winner).zoomDestination(id: winner.id, ns: zoom) }
        }
        .sensoryFeedback(Haptic.tick, trigger: reelIndex)
        // Only when a pick lands (not when it's cleared by Blacklist or Not
        // tonight). The full-screen reveal plays its own as it lands.
        .sensoryFeedback(Haptic.decided, trigger: winner) { _, new in new != nil && !useReveal }
        .onChange(of: resetKey) { reset() }
        // The reveal finished (or was tapped away): land on the pick.
        .onChange(of: reveal == nil) {
            guard reveal == nil, let pending else { return }
            self.pending = nil
            land(pending.place, at: pending.index)
        }
        // "Spin for it" / "Spin my favorites" from another tab.
        .onAppear { consumePendingSpin() }
        .onChange(of: model.pendingSpin) { consumePendingSpin() }
        .onChange(of: pool.count) { consumePendingSpin() }
        .onChange(of: model.isLoading) { consumePendingSpin() }
        // Asked for while a spin was still running: go once it lands.
        .onChange(of: isSpinning) { if !isSpinning { consumePendingSpin() } }
    }

    private func consumePendingSpin() {
        guard model.pendingSpin, !isSpinning else { return }
        guard !pool.isEmpty else {
            // Still searching: wait for results. Nothing to spin: give up quietly.
            if !model.isLoading { model.pendingSpin = false }
            return
        }
        model.pendingSpin = false
        Task { @MainActor in
            // Let the tab switch settle so you see the reel start.
            try? await Task.sleep(for: .milliseconds(350))
            spin(pool)
        }
    }

    private func reel(_ pool: [Place]) -> some View {
        let count = pool.count
        let current = count > 0 ? pool[reelIndex % count] : nil
        let previous = count > 1 ? pool[(reelIndex - 1 + count) % count].name : " "
        let next = count > 1 ? pool[(reelIndex + 1) % count].name : " "
        let landed = winner != nil && !isSpinning
        // Before a spin: no names yet, so it never looks like it already picked.
        let idle = !isSpinning && winner == nil && count > 0

        return VStack(spacing: 14) {
            if idle {
                IdleBar(width: 190)
            } else {
                // Once it lands, only the pick shows (no neighbors that read like runners-up).
                Text(previous).font(Theme.body(17, .semibold)).foregroundStyle(Theme.muted.opacity(0.35))
                    .opacity(landed ? 0 : 1)
            }
            HStack(spacing: 12) {
                if idle {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 40, height: 40)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                    Text("Ready to spin")
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.muted)
                } else if let current {
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
            if idle {
                IdleBar(width: 150)
            } else {
                Text(next).font(Theme.body(17, .semibold)).foregroundStyle(Theme.muted.opacity(0.35))
                    .opacity(landed ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .card(radius: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(idle ? "Ready to spin, \(count) places" : (current.map { "Reel showing \($0.name)" } ?? "Reel is empty"))
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
        // Your own wheel needs at least two to be a choice.
        .disabled(isSpinning || pool.count < minimumToSpin)
        .opacity(pool.count < minimumToSpin ? 0.4 : 1)
        .accessibilityLabel(isSpinning ? "Spinning" : (winner == nil ? "Spin" : "Spin again"))
    }

    private func resultCard(_ place: Place) -> some View {
        // Something you typed onto your wheel ("Leftovers") isn't a real place.
        let isTyped = place.id.hasPrefix("typed|")
        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Your pick", color: Theme.accentText)
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
        .zoomSource(id: place.id, ns: zoom)
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
                           tint: onList == .favorites ? Theme.accentText : Theme.text,
                           isOn: onList == .favorites,
                           haptic: Haptic.tick) {
                    actions.toggle(place, in: .favorites)
                }
                ActionTile(title: "Try",
                           systemImage: onList == .interested ? "bookmark.fill" : "bookmark",
                           tint: onList == .interested ? Theme.accentText : Theme.text,
                           isOn: onList == .interested,
                           haptic: Haptic.tick) {
                    actions.toggle(place, in: .interested)
                }
                ActionTile(title: "Blacklist", systemImage: "nosign", haptic: Haptic.destructive) { blacklist(place) }
            }
            HStack(spacing: 8) {
                Button("See details") { showDetail = true }
                    .font(Theme.body(15, .bold))
                    .foregroundStyle(Theme.night)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.text, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .buttonStyle(.plain)
                SharePickButton(place: place, context: .spin) {
                    Image(systemName: "square.and.arrow.up")
                        .font(Theme.body(17, .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 50, height: 50)
                        .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel("Share your pick")
            }
            // Closed, too far, not in the mood: pass for tonight (not forever) and spin again.
            Button { skipTonight(place) } label: {
                Label("Not tonight · spin again", systemImage: "arrow.uturn.right")
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Leaves it out of spins for a few hours, then spins again")
    }

    private func skipTonight(_ place: Place) {
        model.skipForNow(place)
        let appModel: AppModel = model
        UndoCenter.shared.show("Skipping \(place.name) tonight") { appModel.unskipForNow(place) }
        let rest = pool.filter { $0.id != place.id }
        winner = nil
        guard !rest.isEmpty else {
            message = isHome ? "That was the last one. Maybe it’s a takeout night: switch to Eat out."
                             : "That was the last one. Try a bigger radius or another list."
            return
        }
        spin(rest)
    }

    /// Eat in: the meal, its note, the recipe link, and Not tonight (button or
    /// swipe left, for when you're missing an ingredient).
    private func homeResultCard(_ meal: Place) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Tonight you’re making", color: Theme.accentText)
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name).font(Theme.display(24)).foregroundStyle(Theme.text)
                if let note = notes[meal.id], !note.isEmpty {
                    Text(note).font(Theme.body(14)).foregroundStyle(Theme.muted)
                }
            }
            if let url = meal.websiteURL {
                Button { openURL(url) } label: {
                    Label("Open the recipe", systemImage: "book")
                        .font(Theme.body(15, .bold))
                        .foregroundStyle(Theme.night)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.text, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button { skipTonight(meal) } label: {
                Label("Missing something? Not tonight · spin again", systemImage: "arrow.uturn.right")
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Leaves it out for tonight, then spins again")
        }
        .padding(18)
        .card(radius: 24)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.saffron.opacity(0.35)))
        .overlay(alignment: .trailing) {
            // What a swipe will do, showing as you drag.
            if dragX < -24 {
                Label("Not tonight", systemImage: "arrow.uturn.right")
                    .font(Theme.body(13, .bold))
                    .foregroundStyle(Theme.accentText)
                    .padding(.trailing, 16)
                    .opacity(min(1, Double(-dragX - 24) / 60))
            }
        }
        .offset(x: dragX)
        // Simultaneous, so a drag that starts on the card still scrolls the page.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    // Left only, and mostly sideways (so scrolling still works).
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragX = min(0, value.translation.width)
                }
                .onEnded { value in
                    let skip = dragX < -100  // only sideways drags moved it
                    withAnimation(.snappy) { dragX = 0 }
                    if skip { skipTonight(meal) }
                }
        )
        .accessibilityAction(named: "Not tonight") { skipTonight(meal) }
    }

    // MARK: Logic

    /// Blacklists the result (with Undo). On your own wheel it also comes off
    /// the wheel, and Undo puts it back.
    private func blacklist(_ place: Place) {
        let appModel: AppModel = model
        var putBack: (@MainActor () -> Void)? = nil
        if isPickedWheel {
            // Only put it back if it's still off (toggling again would remove it).
            putBack = {
                if !appModel.pickedWheel.contains(where: { $0.id == place.id }) { appModel.togglePicked(place) }
            }
            appModel.togglePicked(place)
        }
        actions.block(place, extraUndo: putBack)
        winner = nil
    }

    /// Decide the winner up front, then animate the reel slowing down onto it.
    private func spin(_ pool: [Place]) {
        guard !isSpinning else { return }
        Hint.spinFirst.dismiss()
        // Your own wheel spins exactly what you chose. Everything else still
        // prefers places you haven't had lately (the pool is already filtered).
        let choice = (isPickedWheel || isHome) ? pool.randomElement() : Randomizer.pick(from: pool, rules: rulesAtSpin())
        guard let pick = choice, let target = pool.firstIndex(of: pick) else {
            message = "Nothing to spin. Try a bigger radius or fewer filters."
            return
        }
        message = nil
        reelPool = pool
        isSpinning = true
        winner = nil

        if useReveal {
            // The full-screen reveal (as in Group Spin) cycles through up to 16
            // of the places, then lands on the pick; the reel lands with it.
            var names = Array(pool.shuffled().prefix(16)).map(\.name)
            if !names.contains(pick.name) { names[names.count - 1] = pick.name }
            pending = (pick, target)
            reveal = SpinRevealRequest(names: names, winner: pick.name)
            return
        }

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
            land(pick, at: target)
        }
    }

    private func land(_ pick: Place, at target: Int) {
        reelIndex = target
        winner = pick
        landCount += 1
        isSpinning = false
        // Things you typed onto your wheel and home meals aren't restaurants.
        if !pick.id.hasPrefix("typed|") && !HomeRecipe.isRecipe(pick) { actions.recordSpin(pick) }
        UsageStats.record(.spins)
        AccessibilityNotification.Announcement("Your pick: \(pick.name)").post()
    }

    private func reset() {
        guard !isSpinning else { return }
        reelIndex = 0
        winner = nil
        reelPool = []
        message = nil
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

/// A blank line on the reel before the first spin.
private struct IdleBar: View {
    let width: CGFloat
    var body: some View {
        Capsule()
            .fill(Theme.track)
            .frame(width: width, height: 12)
            .frame(height: 22)
            .accessibilityHidden(true)
    }
}

/// The tappable filter row: where on top, everything else under it.
private struct FilterRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Theme.body(15, .semibold))
                .foregroundStyle(Theme.accentText)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(detail)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("Filters")
                .font(Theme.body(13))
                .foregroundStyle(Theme.muted)
            Image(systemName: "chevron.right")
                .font(Theme.body(12, .bold))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
        .contentShape(Rectangle())
    }
}

/// Spin → Nearby filters: where, how far, and what kind of food. The same
/// settings as Discover (changing them here changes them there too).
private struct SpinFiltersSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showLocationPicker = false
    @State private var showMap = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button { showLocationPicker = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: model.isUsingCurrentLocation ? "location.fill" : "mappin")
                                .foregroundStyle(Theme.accentText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Searching near").font(Theme.body(12)).foregroundStyle(Theme.muted)
                                Text(model.locationName).font(Theme.body(16, .semibold)).foregroundStyle(Theme.text)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(Theme.body(12, .bold)).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 56)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Search for a city or neighborhood")

                    HStack(spacing: 8) {
                        if !model.isUsingCurrentLocation && !model.location.isDenied {
                            chip("Use my location", icon: "location.fill") { model.useCurrentLocation() }
                        }
                        chip("Choose on map", icon: "map.fill") { showMap = true }
                        Spacer(minLength: 0)
                    }

                    RadiusSlider(miles: $model.radiusMiles)
                    CuisineChips(selection: $model.cuisines, diet: $model.diet)
                }
                .padding(16)
            }
            .background(Theme.night)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.bold() } }
            .sheet(isPresented: $showLocationPicker) { LocationPickerView() }
            .fullScreenCover(isPresented: $showMap) { FullMapView() }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.night)
    }

    private func chip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(Theme.body(14, .semibold))
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Theme.accentSoft, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
