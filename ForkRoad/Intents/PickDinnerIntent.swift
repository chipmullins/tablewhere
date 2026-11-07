import AppIntents
import Foundation
import PickerCore

/// Which saved list Siri picks from.
enum DinnerSource: String, AppEnum {
    case favorites, wantToTry, nearby

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static var caseDisplayRepresentations: [DinnerSource: DisplayRepresentation] = [
        .favorites: "Favorites",
        .wantToTry: "To try",
        .nearby: "Nearby"
    ]

    func load() -> [Place] {
        switch self {
        case .favorites: return SharedCache.loadFavorites()
        case .wantToTry: return SharedCache.loadInterested()
        case .nearby: return SharedCache.loadClosestNearby()
        }
    }
}

/// "Pick a place to eat": answers with a random place from the shared caches without opening the app.
struct PickDinnerIntent: AppIntent {
    static var title: LocalizedStringResource = "Pick a place to eat"
    static var description = IntentDescription(
        "Picks a random restaurant from your Favorites, To try, or nearby places."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "From",
        description: "Leave empty to try Favorites, then To try, then Nearby."
    )
    var source: DinnerSource?

    static var parameterSummary: some ParameterSummary {
        Summary("Pick a place to eat from \(\.$source)")
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let order: [DinnerSource] = source.map { [$0] } ?? [.favorites, .wantToTry, .nearby]

        for list in order {
            if let place = Randomizer.pick(from: list.load(), rules: SharedCache.pickRules(savedList: list != .nearby)) {
                return .result(dialog: "How about \(place.name)? It's \(place.category), \(place.distanceLabel) away.")
            }
        }

        let message: String
        if let source {
            switch source {
            case .favorites: message = "You don't have any Favorites to pick from yet. Open Tablespin and save a few first."
            case .wantToTry: message = "Your To try list is empty. Open Tablespin and add a few places first."
            case .nearby: message = "I don't have any nearby places yet. Open Tablespin first so it can find restaurants near you."
            }
        } else {
            message = "I don't have any places yet. Open Tablespin first so it can find restaurants near you."
        }
        return .result(dialog: "\(message)")
    }
}
