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

    @State private var reelIndex = 0
    /// Frozen copy of the pool while spinning/landed, so new search results
    /// arriving mid-spin can't change what the reel shows.
    @State private var reelPool: [Place] = []
    @State private var isSpinning = false
    @State private var winner: Place?
    @State private var showDetail = false

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
        case .interested: source = saved.map { $0.asPlace(from: model.center) }
        }
        return Randomizer.eligible(source, rules: rules)
    }

    var body: some View {
        @Bindable var model = model
        let pool = self.pool
        let shown = (isSpinning || winner != nil) ? reelPool : pool

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Feeling lucky?")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)

                Picker("Pick from", selection: $model.spinSource) {
                    ForEach(SpinSource.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: model.spinSource) { reset() }

                NoFastFoodChip()

                rulesSummary(count: pool.count)

                reel(shown)

                HStack {
                    Spacer()
                    spinButton(pool)
                    Spacer()
                }

                if let winner, !isSpinning {
                    resultCard(winner)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.spring(duration: 0.4), value: winner)
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
        let parts: [String?] = [
            model.spinSource == .nearby ? "Within \(model.radiusLabel)" : "From your saved places",
            "\(count) in the wheel",
            blockedPlaces.isEmpty && blockedCategories.isEmpty ? nil : "Skips \(blockedPlaces.count + blockedCategories.count) blocked",
            model.excludeFastFood ? "No fast food" : nil,
            "No repeats this week"
        ]
        let labels = parts.compactMap { $0 }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(labels, id: \.self) { part in
                    Text(part)
                        .font(.system(size: 12, weight: .semibold))
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
            Text(previous).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted.opacity(0.35))
            HStack(spacing: 12) {
                if let current {
                    MonogramTile(name: current.name, size: 40)
                    Text(current.name)
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(model.spinSource == .interested ? "Save some places first" : "No places in range")
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
            Text(next).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted.opacity(0.35))
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .card(radius: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current.map { "Reel showing \($0.name)" } ?? "Reel is empty")
    }

    private func spinButton(_ pool: [Place]) -> some View {
        Button { spin(pool) } label: {
            Text(isSpinning ? "…" : (winner == nil ? "Spin" : "Again"))
                .font(Theme.display(20))
                .foregroundStyle(Theme.onSaffron)
                .frame(width: 104, height: 104)
                .background(Theme.saffron, in: Circle())
                .overlay(Circle().strokeBorder(Color(hex: 0x2A2214), lineWidth: 6))
                .shadow(color: Theme.saffron.opacity(0.28), radius: 20, y: 12)
        }
        .buttonStyle(.plain)
        .disabled(isSpinning || pool.isEmpty)
        .opacity(pool.isEmpty ? 0.4 : 1)
        .accessibilityLabel("Spin")
    }

    private func resultCard(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Tonight’s pick", color: Theme.saffron)
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).font(Theme.display(24)).foregroundStyle(Theme.text)
                Text("\(place.category) · \(place.distanceLabel)")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                ActionTile(title: "Call", systemImage: "phone") {
                    if let url = PlaceLinks.phoneURL(place) { openURL(url) }
                }
                .disabled(place.phoneNumber == nil)
                ActionTile(title: "Go", systemImage: "location.north.line") {
                    PlaceLinks.openDirections(place)
                }
                ActionTile(title: actions.isSaved(place) ? "Saved" : "Save",
                           systemImage: actions.isSaved(place) ? "heart.fill" : "heart",
                           tint: actions.isSaved(place) ? Theme.saffron : Theme.text) {
                    actions.toggleSaved(place)
                }
                ActionTile(title: "Not this", systemImage: "nosign") {
                    actions.block(place)
                    winner = nil
                }
            }
            Button("See details") { showDetail = true }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.night)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.text, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .buttonStyle(.plain)
        }
        .padding(18)
        .card(radius: 24)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.saffron.opacity(0.35)))
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
            isSpinning = false
            actions.recordSpin(pick)
        }
    }

    private func reset() {
        guard !isSpinning else { return }
        reelIndex = 0
        winner = nil
        reelPool = []
    }
}
