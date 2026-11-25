import SwiftUI
import SwiftData
import PickerCore

/// Spin's home (1.2 sleek layout): the map with your places on the top half,
/// where and filters as floating pills over it, and a bottom sheet with
/// "Tonight?", Eat out / Eat in, one big Spin button and a one-line summary.
/// A landed pick takes over the screen (SpinResultView).
struct SpinView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query private var areas: [SavedArea]
    @Query(sort: \HomeRecipe.name) private var recipes: [HomeRecipe]

    @State private var showFilters = false
    @State private var showLocationPicker = false
    @State private var showFullMap = false
    @State private var showAddRecipe = false
    @State private var showWheelPicker = false
    /// The full-screen reveal (same as Group Spin) while it plays.
    @State private var reveal: SpinRevealRequest?
    /// The pick that landed, shown full screen until you close it or spin again.
    @State private var result: SpinResult?
    /// Asks the stage to spin (from the result's "Not tonight · spin again").
    @State private var spinRequest: SpinRequest?

    private var actions: ListActions { ListActions(context: context) }

    private var rules: Randomizer.Rules {
        var rules = model.rules(
            blockedPlaces: blockedPlaces,
            blockedCategories: blockedCategories,
            recent: actions.recentPlaceIDs(),
            // Saved places are the user's own picks, so the radius doesn't apply to them.
            maxDistance: model.spinSource == .nearby ? model.radiusMeters : nil
        )
        // A coffee shop you saved yourself still spins.
        if model.spinSource != .nearby { rules.excludeCoffeeAndSweets = false }
        return rules
    }

    /// Everything that could come up on the wheel.
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

    private var isPickedWheel: Bool { !model.eatIn && model.spinSource == .picked }

    var body: some View {
        let pool = self.pool

        ZStack {
            if let result {
                SpinResultView(
                    result: result,
                    notes: recipeNotes,
                    onClose: { withAnimation(Motion.standard) { self.result = nil } },
                    onNotTonight: { skipTonight(result.place) },
                    onSpinAgain: { spinAgain(pool) },
                    onBlacklist: { blacklist(result.place) }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                home(pool)
                    .transition(.opacity)
            }
        }
        .animation(Motion.standard, value: result?.id)
        .background(Theme.night)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if let reveal {
                SpinReveal(names: reveal.names, winner: reveal.winner) { self.reveal = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: reveal?.id)
        // A pick that lands (not one cleared by Blacklist or Not tonight). The
        // full-screen reveal plays its own as it lands.
        .sensoryFeedback(Haptic.decided, trigger: result?.id) { _, new in
            new != nil && !useReveal
        }
        .onChange(of: model.spinSource) {
            if model.spinSource == .picked { Hint.myWheel.dismiss() }
        }
        .onChange(of: model.eatIn) { if model.eatIn { Hint.eatIn.dismiss() } }
        // Changing where or what you spin closes an old pick.
        .onChange(of: resetKey) { result = nil }
        // "Spin for it" from another tab while a pick is open: back to the wheel.
        .onChange(of: model.pendingSpin) { if model.pendingSpin { result = nil } }
        .sheet(isPresented: $showAddRecipe) { RecipeForm() }
        .sheet(isPresented: $showFilters) { SearchFiltersSheet() }
        .sheet(isPresented: $showLocationPicker) { LocationPickerView() }
        .sheet(isPresented: $showWheelPicker) { WheelPickerSheet() }
        .fullScreenCover(isPresented: $showFullMap) { FullMapView() }
    }

    @AppStorage("spinReveal") private var useReveal = true

    // MARK: Home

    private func home(_ pool: [Place]) -> some View {
        GeometryReader { geo in
            // The map fills the top half (and up under the status bar); the
            // sheet overlaps it a little and scrolls up over it when it's long.
            let mapHeight = max(260, geo.size.height * 0.5 + geo.safeAreaInsets.top)
            ZStack(alignment: .top) {
                hero(pool)
                    .frame(height: mapHeight)
                    .frame(maxWidth: .infinity)
                    .ignoresSafeArea(edges: .top)

                ScrollView {
                    VStack(spacing: 0) {
                        // Tapping the map (above the sheet) opens the big one.
                        Color.clear
                            .frame(height: max(0, mapHeight - geo.safeAreaInsets.top - 40))
                            .contentShape(Rectangle())
                            .onTapGesture { if !model.eatIn { showFullMap = true } }
                            .accessibilityElement()
                            .accessibilityLabel(model.eatIn ? "" : "Map of \(plural(pool.count, "place")). Opens a bigger map.")
                            .accessibilityAddTraits(model.eatIn ? [] : .isButton)
                            .accessibilityHidden(model.eatIn)
                        sheet(pool)
                    }
                }
                .scrollIndicators(.hidden)

                if !model.eatIn { pills.padding(.top, 8) }
            }
        }
    }

    /// The top half: the map with your places, or (Eat in) a warm kitchen card.
    @ViewBuilder
    private func hero(_ pool: [Place]) -> some View {
        if model.eatIn {
            ZStack {
                Theme.accentSoft
                Image(systemName: "frying.pan")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Theme.accentText.opacity(0.35))
                    .offset(y: -10)
            }
            .accessibilityHidden(true)
        } else {
            NearbyMap(places: mapPlaces(pool), isHero: true, showsRadius: model.spinSource == .nearby)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Pins for the map: real places only (not things typed onto your wheel).
    private func mapPlaces(_ pool: [Place]) -> [Place] {
        pool.filter { !$0.id.hasPrefix("typed|") }
    }

    /// Where you're spinning, and the filters, floating over the map.
    private var pills: some View {
        HStack(spacing: 8) {
            Button { showLocationPicker = true } label: {
                FloatingPill {
                    HStack(spacing: 8) {
                        Image(systemName: model.isUsingCurrentLocation ? "location.fill" : "mappin.and.ellipse")
                            .foregroundStyle(Theme.accentText)
                        Text(locationPillText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Spinning near \(model.locationName)\(model.spinSource == .nearby ? ", within \(model.radiusLabel)" : ""). Change location")

            if model.spinSource == .nearby {
                Button { showFilters = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 48, height: 48)
                        .background(Theme.floating, in: Circle())
                        .shadow(color: .black.opacity(0.1), radius: 9, y: 6)
                        .overlay(alignment: .topTrailing) {
                            if activeFilterCount > 0 {
                                Text("\(activeFilterCount)")
                                    .font(Theme.body(11, .bold))
                                    .foregroundStyle(Theme.onSaffron)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(Theme.saffron, in: Circle())
                                    .offset(x: 2, y: -2)
                            }
                        }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Filters")
                .accessibilityValue(nearbyFilterDetail)
                .accessibilityHint("Change where, how far, and what kind of food")
            }
        }
        .padding(.horizontal, 16)
    }

    private var locationPillText: String {
        model.spinSource == .nearby ? "\(model.locationName) · \(model.radiusLabel)" : model.locationName
    }

    /// Filters that narrow Nearby (cuisines, diet, no fast food).
    private var activeFilterCount: Int {
        (model.cuisines.isEmpty ? 0 : 1) + (model.diet == .none ? 0 : 1) + (model.excludeFastFood ? 1 : 0)
    }

    // MARK: The sheet

    private func sheet(_ pool: [Place]) -> some View {
        @Bindable var model = model
        return VStack(spacing: 18) {
            SheetGrabber().padding(.top, 2)

            HStack(alignment: .firstTextBaseline) {
                Text("Tonight?")
                    .font(Theme.display(28))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(countLine(pool.count))
                    .font(Theme.body(13, .medium))
                    .foregroundStyle(Theme.muted)
            }

            SleekSegmented(title: "Eat out or in",
                           options: [(label: "Eat out", value: false), (label: "Eat in", value: true)],
                           selection: $model.eatIn.animation(.snappy))

            if model.eatIn {
                eatInHeader
            } else {
                eatOutControls
                LateNightNote(placeCount: pool.count)
            }

            SpinStage(pool: pool,
                      resetKey: resetKey,
                      emptyText: emptyReelText,
                      footnote: footnote(count: pool.count),
                      isPickedWheel: isPickedWheel,
                      isHome: model.eatIn,
                      rulesAtSpin: { rules },
                      reveal: $reveal,
                      result: $result,
                      spinRequest: $spinRequest)

            if !model.eatIn {
                HintCard(.spinFirst)
                HintCard(.myWheel)
                HintCard(.eatIn)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            // Runs past the bottom so the cream never ends above the tab bar.
            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.sheet, topTrailingRadius: Theme.Radius.sheet,
                                   style: .continuous)
                .fill(Theme.night)
                .shadow(color: .black.opacity(0.08), radius: 15, y: -10)
                .padding(.bottom, -600)
        }
    }

    /// Eat out: where to pick from, and that source's own controls.
    @ViewBuilder
    private var eatOutControls: some View {
        @Bindable var model = model
        SleekSegmented(title: "Pick from",
                       options: SpinSource.allCases.map { (label: $0.label, value: $0) },
                       selection: $model.spinSource,
                       height: 36)

        switch model.spinSource {
        case .nearby:
            EmptyView()  // the pills over the map
        case .picked:
            PickedWheelEditor(showPicker: $showWheelPicker)
        case .favorites, .interested:
            HStack(spacing: 8) {
                CityMenu(metros: saved.filter { $0.list == model.spinSource.savedList }.metros)
                NoFastFoodChip()
                Spacer(minLength: 0)
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
                    .accessibilityHidden(true)
                Text("\(recipes.count) home meal\(recipes.count == 1 ? "" : "s")")
                    .font(Theme.body(15, .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button { showAddRecipe = true } label: {
                    Label("Add", systemImage: "plus")
                        .font(Theme.body(14, .bold))
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.pressable)
                Button("Edit") {
                    model.showHomeList = true
                    model.selectedTab = .lists
                }
                .font(Theme.body(14, .bold))
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 44)
                .buttonStyle(.pressable)
                .accessibilityHint("Opens your Home list in Lists")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        }
    }

    /// Recipe notes by reel ID, for the result.
    private var recipeNotes: [String: String] {
        Dictionary(recipes.map { ($0.asSpinItem.id, $0.note) }, uniquingKeysWith: { first, _ in first })
    }

    /// When any of these change, the wheel starts over.
    private var resetKey: String {
        [model.eatIn ? "in" : "out", model.spinSource.rawValue, "\(model.listCity)", "\(model.center.latitude),\(model.center.longitude)",
         "\(model.radiusMiles)", model.pickedWheel.map(\.id).joined(separator: ",")].joined(separator: "|")
    }

    // MARK: Result actions

    private func skipTonight(_ place: Place) {
        model.skipForNow(place)
        let appModel: AppModel = model
        UndoCenter.shared.show("Skipping \(place.name) tonight") { appModel.unskipForNow(place) }
        let rest = pool.filter { $0.id != place.id }
        withAnimation(Motion.standard) { result = nil }
        guard !rest.isEmpty else {
            spinRequest = SpinRequest(pool: [], lastOneMessage: model.eatIn
                ? "That was the last one. Maybe it’s a takeout night: switch to Eat out."
                : "That was the last one. Try a bigger radius or another list.")
            return
        }
        spinRequest = SpinRequest(pool: rest)
    }

    private func spinAgain(_ pool: [Place]) {
        withAnimation(Motion.standard) { result = nil }
        spinRequest = SpinRequest(pool: pool)
    }

    /// Blacklists the pick (with Undo). On your own wheel it also comes off
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
        withAnimation(Motion.standard) { result = nil }
    }

    // MARK: Words

    /// "21 places nearby", "4 meals", "6 on your wheel".
    private func countLine(_ count: Int) -> String {
        if model.eatIn { return plural(count, "meal") }
        switch model.spinSource {
        case .nearby:
            if !model.hasSearched || (model.isLoading && count == 0) { return "Looking nearby…" }
            return "\(plural(count, "place")) nearby"
        case .picked: return "\(count) on your wheel"
        case .favorites: return plural(count, "favorite")
        case .interested: return "\(count) to try"
        }
    }

    /// "2 mi · All cuisines · No fast food", for VoiceOver on the Filters button.
    private var nearbyFilterDetail: String {
        var parts = [model.radiusLabel,
                     model.cuisines.isEmpty ? "All cuisines" : model.cuisineSummary]
        if model.diet != .none { parts.append(model.diet.label) }
        if model.excludeFastFood { parts.append("No fast food") }
        return parts.joined(separator: " · ")
    }

    /// One quiet line under the Spin button: what the spin will use.
    private func footnote(count: Int) -> String {
        if model.eatIn {
            let skipped = recipes.count - count
            return skipped > 0 ? "\(skipped) not tonight · picks any of your meals" : "Picks any of your home meals"
        }
        if model.spinSource == .picked { return count < 2 ? "Add at least 2 to spin" : "Spins exactly what’s on your wheel" }
        var parts: [String] = []
        if model.spinSource == .nearby {
            if !model.cuisines.isEmpty { parts.append(model.cuisineSummary) }
            if model.diet != .none { parts.append(model.diet.label) }
        } else {
            parts.append(areaChip)
        }
        if model.excludeFastFood { parts.append("No fast food") }
        if skippedCount > 0 { parts.append("\(skippedCount) left out") }
        parts.append("skips places you’ve had lately")
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
        case .nearby:
            if model.location.isDenied && model.isUsingCurrentLocation { return "Location is off. Pick a city above" }
            if !model.hasLocation { return "Pick a location above" }
            if model.errorMessage != nil { return "Can’t reach Apple Maps. Check your connection" }
            if model.isLoading || !model.hasSearched { return "Finding places nearby…" }
            return "No places in range. Try a bigger radius"
        case .picked: return "Add a few places to your wheel"
        case .favorites:
            return model.listCity == .all ? "Heart some favorites first" : "No favorites around here yet"
        case .interested:
            return model.listCity == .all ? "Bookmark places to try first" : "Nothing saved around here yet"
        }
    }
}

/// Asks SpinView to play the full-screen reveal for a spin.
struct SpinRevealRequest: Identifiable, Equatable {
    let id = UUID()
    let names: [String]
    let winner: String
}

/// A pick that landed.
struct SpinResult: Identifiable, Equatable {
    let id = UUID()
    let place: Place
    /// How many were on the wheel ("Picked from 21 places").
    let spunFrom: Int
    /// A home meal (Eat in).
    let isHome: Bool
    /// From your own Custom wheel.
    let isPickedWheel: Bool
}

/// Asks the stage to spin this pool (after "Not tonight" or "Spin again").
/// An empty pool with a message means there's nothing left.
struct SpinRequest: Identifiable, Equatable {
    let id = UUID()
    let pool: [Place]
    var lastOneMessage: String? = nil
}

/// The Spin button and, while it spins without the full-screen reveal, the
/// names rolling by. Owns the spin state so a reel tick only redraws this view.
private struct SpinStage: View {
    let pool: [Place]
    let resetKey: String
    let emptyText: String
    /// "No fast food · skips places you've had lately", under the button.
    let footnote: String
    /// Your own wheel spins exactly what you chose (no rules at spin time).
    let isPickedWheel: Bool
    /// Eat in: the pool holds home meals (see HomeRecipe.asSpinItem).
    var isHome = false
    /// The rules for picking, worked out once when you tap Spin.
    let rulesAtSpin: () -> Randomizer.Rules
    @Binding var reveal: SpinRevealRequest?
    @Binding var result: SpinResult?
    @Binding var spinRequest: SpinRequest?

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var reelIndex = 0
    /// Frozen copy of the pool while spinning, so new search results
    /// arriving mid-spin can't change what the reel shows.
    @State private var reelPool: [Place] = []
    @State private var isSpinning = false
    /// Increments each time a spin lands; drives the burst.
    @State private var landCount = 0
    @State private var message: String?
    /// Settings → "Full-screen spin". On: the Group Spin reveal. Off: the quick reel.
    @AppStorage("spinReveal") private var useReveal = true
    /// The pick waiting for the reveal to finish.
    @State private var pending: Place?

    private var actions: ListActions { ListActions(context: context) }
    private var minimumToSpin: Int { isPickedWheel ? 2 : 1 }
    private var canSpin: Bool { !isSpinning && pool.count >= minimumToSpin }

    var body: some View {
        VStack(spacing: 18) {
            // The quick reel (Full-screen spin off): names roll by in big type.
            if isSpinning && pending == nil && !reelPool.isEmpty {
                reelLine
            } else if pool.isEmpty && !(isPickedWheel && model.pickedWheel.isEmpty) {
                Text(emptyText)
                    .font(Theme.display(18))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            spinButton
                .overlay { LandingBurst(trigger: landCount).allowsHitTesting(false) }
                .padding(.vertical, 6)

            Text(message ?? footnote)
                .font(Theme.body(13, message == nil ? .medium : .semibold))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .opacity(pool.isEmpty && message == nil && !isPickedWheel ? 0 : 1)
        }
        .sensoryFeedback(Haptic.tick, trigger: reelIndex)
        .onChange(of: resetKey) { reset() }
        // The reveal finished (or was tapped away): land on the pick.
        .onChange(of: reveal == nil) {
            guard reveal == nil, let pending else { return }
            self.pending = nil
            land(pending)
        }
        // From the result (this view comes back as the result closes, so on appear too).
        .onChange(of: spinRequest) { consumeSpinRequest() }
        // "Spin for it" / "Spin my favorites" from another tab.
        .onAppear {
            consumeSpinRequest()
            consumePendingSpin()
        }
        .onChange(of: model.pendingSpin) { consumePendingSpin() }
        .onChange(of: pool.count) { consumePendingSpin() }
        .onChange(of: model.isLoading) { consumePendingSpin() }
        // Asked for while a spin was still running: go once it lands.
        .onChange(of: isSpinning) { if !isSpinning { consumePendingSpin() } }
    }

    private var reelLine: some View {
        let count = reelPool.count
        let current = reelPool[((reelIndex % count) + count) % count]
        return HStack(spacing: 12) {
            MonogramTile(name: current.name, category: current.category, size: 40)
            Text(current.name)
                .font(Theme.display(26))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spinning")
    }

    private var spinButton: some View {
        Button { spin(pool) } label: {
            VStack(spacing: 2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .bold))
                    .symbolEffect(.bounce, value: landCount)
                Text(isSpinning ? "Spinning" : "Spin")
                    .font(.custom("Outfit-ExtraBold", size: isSpinning ? 22 : 30, relativeTo: .title))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Theme.onSaffron)
            .frame(width: 150, height: 150)
            .background(Theme.saffron, in: Circle())
            .background(Circle().fill(Theme.accentSoft).padding(-12))
            .shadow(color: Theme.saffron.opacity(0.45), radius: 20, y: 18)
        }
        .buttonStyle(.pressable)
        // Your own wheel needs at least two to be a choice.
        .disabled(!canSpin)
        .opacity(pool.count < minimumToSpin ? 0.4 : 1)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel(isSpinning ? "Spinning" : "Spin")
        .accessibilityHint(canSpin ? "Picks one of \(plural(pool.count, isHome ? "meal" : "place")) for you" : "")
    }

    private func consumeSpinRequest() {
        guard let request = spinRequest, !isSpinning else { return }
        spinRequest = nil
        if let note = request.lastOneMessage, request.pool.isEmpty {
            message = note
        } else {
            spin(request.pool)
        }
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
            // Let the tab switch settle so you see it start.
            try? await Task.sleep(for: .milliseconds(350))
            spin(pool)
        }
    }

    /// Decide the winner up front, then animate onto it.
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

        if useReveal {
            // The full-screen reveal (as in Group Spin) cycles through up to 16
            // of the places, then lands on the pick.
            var names = Array(pool.shuffled().prefix(16)).map(\.name)
            if !names.contains(pick.name) { names[names.count - 1] = pick.name }
            pending = pick
            reveal = SpinRevealRequest(names: names, winner: pick.name)
            return
        }

        // Reduce Motion: no rolling names; a beat, then the pick fades in.
        if reduceMotion {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                land(pick)
            }
            return
        }

        // Start exactly `steps` names before the winner so it lands on it
        // naturally instead of jumping at the end.
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
            land(pick)
        }
    }

    private func land(_ pick: Place) {
        let spunFrom = reelPool.count
        landCount += 1
        isSpinning = false
        reelPool = []
        // Things you typed onto your wheel and home meals aren't restaurants.
        if !pick.id.hasPrefix("typed|") && !HomeRecipe.isRecipe(pick) { actions.recordSpin(pick) }
        UsageStats.record(.spins)
        if HomeRecipe.isRecipe(pick) { UsageStats.record(.eatInSpins) }
        AccessibilityNotification.Announcement("Your pick: \(pick.name)").post()
        // A beat for the burst, then the result takes over.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion || useReveal ? 0 : 260))
            withAnimation(Motion.reveal) {
                result = SpinResult(place: pick, spunFrom: spunFrom, isHome: isHome, isPickedWheel: isPickedWheel)
            }
        }
    }

    private func reset() {
        guard !isSpinning else { return }
        reelIndex = 0
        reelPool = []
        message = nil
    }
}

/// A quick saffron burst from the Spin button when a spin lands.
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
                    let point = CGPoint(x: center.x + cos(angle) * distance * 1.2,
                                        y: center.y + sin(angle) * distance * 1.2)
                    let radius = (i % 3 == 0 ? 5.0 : 3.5) * (1 - progress * 0.6)
                    let color = i % 4 == 0 ? Theme.accentText : Color(hex: 0xFFB23F)
                    context.opacity = Double(1 - progress)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                        width: radius * 2, height: radius * 2)),
                                 with: .color(color))
                }
            }
            .frame(width: 320, height: 320)
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
