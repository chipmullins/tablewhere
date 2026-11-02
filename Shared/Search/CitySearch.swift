import Foundation
import MapKit
import Observation

/// Place autocomplete backed by MKLocalSearchCompleter.
/// `citiesOnly` drops street addresses; otherwise addresses,
/// neighborhoods, and landmarks are all allowed (changing your location).
@MainActor
@Observable
final class CitySearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var results: [MKLocalSearchCompletion] = []

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private let citiesOnly: Bool

    init(citiesOnly: Bool = true) {
        self.citiesOnly = citiesOnly
        super.init()
        completer.resultTypes = citiesOnly ? .address : [.address, .pointOfInterest]
        completer.delegate = self
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let all = completer.results
        // Cities have no street number, so that drops street addresses.
        let filtered = citiesOnly ? all.filter { !$0.title.contains(where: \.isNumber) } : all
        Task { @MainActor in self.results = Array(filtered.prefix(12)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
