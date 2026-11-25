import SwiftUI
import SwiftData
import PickerCore
import CoreLocation

/// Sheet for starting a group plan: how you'll decide, a name, then the
/// places (chosen in their own sheet, or drawn from nearby for Surprise us).
struct CreateGroupView: View {
    /// A place picked already (Spin → "Make it a group plan"): starts as "I'll pick" with it.
    var startingPlace: Place? = nil
    var onCreated: (GroupSession) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Query private var blockedPlaces: [BlockedPlace]
    @Query private var blockedCategories: [BlockedCategory]

    @State private var title = ""
    @State private var setup: SetupMode = .vote
    @State private var closesIn: Int? = nil
    @State private var selected: [Place] = []
    @State private var showPicker = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    /// An area picked in the place picker (or Surprise us); saved on the plan for everyone.
    @State private var pickedArea: PickerArea?
    @State private var startTaps = 0
    // Surprise us (its own area, so switching modes doesn't mix them up)
    @State private var surpriseArea: PickerArea?
    @State private var surpriseFilters: PlacePickerFilters?
    @State private var wheel: [Place] = []
    @State private var isLoadingWheel = true
    /// Vote, spin, and Surprise us: "Set a date & time" (I'll pick always has one).
    @State private var hasTime = false
    /// Vote and Spin our picks: No fast food / No coffee & sweets for everyone (off by default).
    @State private var groupFilters = GroupFilters()
    private var usesGroupFilters: Bool { setup == .vote || setup == .spin }
    /// Your own places that the filters you turned on don't allow.
    private var picksBreakingFilters: [Place] {
        usesGroupFilters ? selected.filter { !groupFilters.allows($0) } : []
    }
    // "I'll pick" (and the optional time for the others)
    @State private var meetTime = PlanSetupRows.defaultMeetTime()
    @State private var note = ""
    @State private var asksRSVP = false
    @State private var hasReplyBy = false
    @State private var replyBy = PlanSetupRows.defaultReplyBy(for: PlanSetupRows.defaultMeetTime())
    /// An "I'll pick" plan that was just made: the share sheet opens with it
    /// (the button said "Send the plan"), then you land on the plan.
    @State private var createdPlan: GroupSession?
    /// The same plan, kept until the share sheet has closed.
    @State private var sessionBeingShared: GroupSession?

    static let maxVoteOptions = GroupMode.maxStartingVoteOptions
    /// In a spin everyone adds one place, starting with you; a plan has one.
    private var maxOptions: Int { setup == .vote ? Self.maxVoteOptions : 1 }
    private var isSingle: Bool { setup != .vote }

    private var rules: Randomizer.Rules {
        model.rules(blockedPlaces: blockedPlaces, blockedCategories: blockedCategories)
    }
    private func savedPlaces(in list: SavedList) -> [Place] {
        saved.filter { $0.list == list && $0.isShareable }.map { $0.asPlace(from: model.center) }
    }

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                nameSection

                switch setup {
                case .surprise:
                    SurpriseWheelSection(
                        center: model.hasLocation ? model.center : nil,
                        centerName: model.locationName,
                        startingFilters: PlacePickerFilters(model.searchArea),
                        startingNearby: model.places,
                        rules: rules,
                        search: model.placeSearch,
                        area: $surpriseArea,
                        filters: Binding(get: { surpriseFilters ?? PlacePickerFilters(model.searchArea) },
                                         set: { surpriseFilters = $0 }),
                        wheel: $wheel,
                        isLoading: $isLoadingWheel
                    )
                case .vote, .spin, .plan:
                    placesSection
                    if usesGroupFilters { groupFiltersSection }
                    if setup == .plan {
                        PlanSetupRows(meetTime: $meetTime, note: $note, asksRSVP: $asksRSVP,
                                      hasReplyBy: $hasReplyBy, replyBy: $replyBy)
                    }
                }
                if setup != .plan { PlanWhenSection(hasTime: $hasTime, meetTime: $meetTime) }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                        .listRowBackground(Theme.surface)
                }
            }
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
            .background(Theme.night)
            .sensoryFeedback(Haptic.tick, trigger: setup)
            .onChange(of: setup) {
                if isSingle && selected.count > 1 { selected = Array(selected.prefix(1)) }
            }
            // Don't lose your picks to a stray swipe.
            .interactiveDismissDisabled(!selected.isEmpty)
            // From a spin: "I'll pick" with that place, ready to set a time and send.
            .onAppear {
                if let startingPlace, selected.isEmpty {
                    setup = .plan
                    selected = [startingPlace]
                }
            }
            .sensoryFeedback(Haptic.commit, trigger: startTaps)
            .navigationTitle("New group plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(isPresented: $showPicker) { pickerSheet }
            .sheet(item: $createdPlan, onDismiss: finishPlan) { plan in
                ActivityView(items: [planMessage(plan)])
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
        .presentationBackground(Theme.night)
    }

    // MARK: Sections

    /// The four ways to decide, each with a line saying what it means.
    private var modeSection: some View {
        Section {
            ForEach(SetupMode.allCases) { option in
                Button {
                    withAnimation(.snappy) { setup = option }
                } label: {
                    SetupModeRow(option: option, isOn: setup == option)
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(setup == option ? .isSelected : [])
            }
            if setup == .vote {
                Picker("Voting closes", selection: $closesIn) {
                    Text("When I lock it in").tag(Int?.none)
                    Text("In 5 min").tag(Int?.some(5))
                    Text("In 15 min").tag(Int?.some(15))
                    Text("In 30 min").tag(Int?.some(30))
                }
            }
        } header: {
            Text("How do you want to decide?")
        }
        .listRowBackground(Theme.surface)
    }

    private var nameSection: some View {
        Section {
            TextField(setup.defaultTitle, text: $title)
        } header: {
            Text("Name")
        }
        .listRowBackground(Theme.surface)
    }

    /// What you've chosen, and a button that opens the place picker.
    private var placesSection: some View {
        Section {
            ForEach(selected) { place in
                HStack(spacing: 12) {
                    MonogramTile(name: place.name, category: place.category, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(place.name).font(Theme.body(15, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(place.category).font(Theme.body(12)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer()
                    Button { toggle(place) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Remove \(place.name)")
                }
            }
            Button {
                // The picker starts at the usual area; keep what's saved on the plan in step.
                pickedArea = nil
                showPicker = true
            } label: {
                Label(addTitle, systemImage: selected.isEmpty ? "plus.circle.fill" : "magnifyingglass")
                    .font(Theme.body(15, .bold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(setup == .vote && selected.count >= maxOptions)
        } header: {
            Text(placesHeader)
        } footer: {
            if setup == .vote {
                Text("Start with 2–\(Self.maxVoteOptions). Friends can suggest one each, up to \(GroupSession.maxOptions) in all.")
            } else if setup == .spin {
                Text("Friends add theirs from the link. You spin when everyone’s in.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var groupFiltersSection: some View {
        Section {
            GroupFiltersRow(filters: $groupFilters)
        } footer: {
            if let place = picksBreakingFilters.first {
                Text("\(place.name) doesn’t fit these filters. Remove it or turn the filter off.")
                    .foregroundStyle(Theme.danger)
            } else {
                Text(groupFilters.isActive
                     ? "Friends can’t add places that break these. You can change them while it’s open."
                     : "Off unless you turn them on.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var placesHeader: String {
        switch setup {
        case .vote: return selected.isEmpty ? "Places" : "Places (\(selected.count) of \(maxOptions))"
        case .spin: return "Your pick"
        default: return "The place"
        }
    }

    private var addTitle: String {
        switch setup {
        case .vote: return selected.isEmpty ? "Add places" : "Add more"
        case .spin: return selected.isEmpty ? "Choose your pick" : "Change your pick"
        default: return selected.isEmpty ? "Choose the place" : "Change the place"
        }
    }

    /// The full picker (search, nearby with filters, your lists), in its own sheet.
    private var pickerSheet: some View {
        NavigationStack {
            PickerSheetContent(
                center: model.center,
                centerName: model.locationName,
                favorites: savedPlaces(in: .favorites),
                interested: savedPlaces(in: .interested),
                startingFilters: PlacePickerFilters(model.searchArea),
                startingNearby: model.places,
                rules: rules,
                search: model.placeSearch,
                selected: selected,
                maxOptions: maxOptions,
                isSingle: isSingle,
                title: addTitle,
                groupFilters: usesGroupFilters && groupFilters.isActive ? groupFilters : nil,
                onAreaChange: { pickedArea = $0 },
                onTap: { place in
                    toggle(place)
                    if isSingle && selected.contains(place) { showPicker = false }
                },
                onDone: { showPicker = false }
            )
        }
        .presentationBackground(Theme.night)
    }

    // MARK: Start

    /// Where things stand, and Start (greyed out with the reason until ready).
    private var bottomBar: some View {
        VStack(spacing: 8) {
            Text(statusLine)
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Button { create() } label: {
                HStack(spacing: 8) {
                    if isCreating { ProgressView().tint(Theme.onSaffron) }
                    Text(setup.startTitle)
                }
                .font(Theme.display(17))
                .foregroundStyle(canCreate ? Theme.onSaffron : Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(canCreate ? Theme.saffron : Theme.surfaceHigh,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.pressable)
            .disabled(!canCreate || isCreating)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.night)
        .animation(.snappy, value: canCreate)
    }

    /// What's missing, or what you're about to start.
    private var statusLine: String {
        if setup != .plan && hasTime && meetTime.timeIntervalSinceNow <= 0 { return "Pick a time that hasn’t passed" }
        if !picksBreakingFilters.isEmpty { return "A place doesn’t fit your group filters" }
        switch setup {
        case .vote:
            if selected.count < 2 { return "Add at least 2 places" }
            return "\(selected.count) places to vote on"
        case .spin:
            return selected.first.map { "Your pick: \($0.name)" } ?? "Choose your pick to start"
        case .surprise:
            if isLoadingWheel && wheel.isEmpty { return "Finding places nearby…" }
            if wheel.count < 2 { return "Need 2+ places nearby. Try a bigger radius." }
            return "\(wheel.count) places on the wheel"
        case .plan:
            guard let place = selected.first else { return "Choose the place to send the plan" }
            if meetTime.timeIntervalSinceNow <= 0 { return "Pick a time that hasn’t passed" }
            return "\(place.name) · \(MeetTimes.label(for: meetTime))"
        }
    }

    private var canCreate: Bool {
        if setup != .plan && hasTime && meetTime.timeIntervalSinceNow <= 0 { return false }
        if !picksBreakingFilters.isEmpty { return false }
        switch setup {
        case .vote: return selected.count >= 2
        case .spin: return selected.count >= 1
        case .surprise: return wheel.count >= 2 && !isLoadingWheel
        case .plan: return selected.count == 1 && meetTime.timeIntervalSinceNow > 0
        }
    }

    /// What you typed, or the default name.
    private var groupTitle: String {
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? setup.defaultTitle : String(typed.prefix(60))
    }

    private func toggle(_ place: Place) {
        if let index = selected.firstIndex(of: place) {
            selected.remove(at: index)
        } else if isSingle {
            selected = [place]  // one pick: tapping another swaps it
        } else if selected.count < maxOptions {
            selected.append(place)
        }
    }

    /// What goes to the group chat: the plan, the time, the note, and the link.
    private func planMessage(_ plan: GroupSession) -> String {
        guard let winner = plan.winner else { return plan.title }
        return GroupLobbyView.planText(plan, winner: winner, note: plan.note)
    }

    /// The share sheet closed (sent or not): on to the plan, where "Send
    /// everyone the plan" is still there if they backed out.
    private func finishPlan() {
        guard let session = sessionBeingShared else { return }
        sessionBeingShared = nil
        onCreated(session)
    }

    /// Where everyone else's picker starts: the area you picked here, else
    /// where you're searching. ("Near you" would mean them, so it gets a real name.)
    private func groupArea(creatorName: String) -> GroupArea? {
        let chosen = setup == .surprise ? surpriseArea : pickedArea
        if let chosen { return chosen.groupArea }
        guard model.hasLocation else { return nil }
        let name = model.isUsingCurrentLocation
            ? (model.location.placeName ?? model.currentCity ?? "\(creatorName)’s area")
            : model.locationName
        return GroupArea(name: name, latitude: model.center.latitude, longitude: model.center.longitude)
    }

    private func create() {
        guard let name = Identity.displayName, canCreate else { return }
        startTaps += 1
        isCreating = true
        errorMessage = nil
        let mode = setup.groupMode
        let isPlan = setup == .plan
        let places = setup == .surprise ? wheel : selected
        Task {
            defer { isCreating = false }
            do {
                let session = try await GroupService.shared.createSession(
                    title: groupTitle,
                    mode: mode,
                    // Surprise us: the rows say "added by the wheel", not you.
                    options: places.map { GroupOption(place: $0, addedBy: setup == .surprise ? "the wheel" : name) },
                    closesInMinutes: setup == .vote ? closesIn : nil,
                    displayName: name,
                    area: groupArea(creatorName: name),
                    meetTime: isPlan || hasTime ? meetTime : nil,
                    note: isPlan ? note : nil,
                    asksRSVP: isPlan && asksRSVP,
                    rsvpBy: isPlan && asksRSVP && hasReplyBy ? PlanSetupRows.clampedReplyBy(replyBy, meetTime: meetTime) : nil,
                    surprise: setup == .surprise,
                    expectedCount: nil,
                    groupFilters: usesGroupFilters ? groupFilters : nil
                )
                if session.mode == .plan {
                    // Share first; onCreated runs when the sheet closes.
                    sessionBeingShared = session
                    createdPlan = session
                } else {
                    onCreated(session)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// The place picker in its own sheet: search, nearby with filters, your
/// lists. One-pick modes close it as soon as you choose.
private struct PickerSheetContent: View {
    let center: CLLocationCoordinate2D
    let centerName: String
    let favorites: [Place]
    let interested: [Place]
    let startingFilters: PlacePickerFilters
    let startingNearby: [Place]
    let rules: Randomizer.Rules
    let search: PlaceSearching
    let selected: [Place]
    let maxOptions: Int
    let isSingle: Bool
    let title: String
    var groupFilters: GroupFilters?
    var onAreaChange: (PickerArea?) -> Void
    var onTap: (Place) -> Void
    var onDone: () -> Void

    @State private var query = ""

    var body: some View {
        Form {
            GroupPlacePicker(
                query: query,
                center: center,
                centerName: centerName,
                favorites: favorites,
                interested: interested,
                startingFilters: startingFilters,
                startingNearby: startingNearby,
                rules: rules,
                groupFilters: groupFilters,
                search: search,
                accessory: { .check(isOn: selected.contains($0)) },
                isDisabled: { !isSingle && !selected.contains($0) && selected.count >= maxOptions },
                onAreaChange: onAreaChange,
                onTap: onTap
            )
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.night)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search restaurants or cravings")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone).bold() }
        }
        // Done stays reachable when iOS 26's search field covers the nav bar.
        .safeAreaInset(edge: .bottom) {
            if !isSingle {
                Button(action: onDone) {
                    Text(selected.isEmpty ? "Done" : "Done · \(selected.count) of \(maxOptions)")
                        .font(Theme.display(17))
                        .foregroundStyle(Theme.onSaffron)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.pressable)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.night)
            }
        }
    }
}
