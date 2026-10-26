import Foundation
import PickerCore

/// The widget's pick logic, shared by the timeline provider and `SpinAgainIntent`.
///
/// A pick is deterministic for a given (seed, 3-hour slot) pair, so the provider can lay
/// out a day of entries ahead of time and "Spin again" only has to change the seed.
enum WidgetPick {
    enum Source: String {
        case favorites, interested, nearby

        var label: String {
            switch self {
            case .favorites: return "From Favorites"
            case .interested: return "From Want to Try"
            case .nearby: return "Nearby"
            }
        }
    }

    struct Result {
        let place: Place
        let source: Source
    }

    static let seedKey = "widget.pickSeed"

    /// How long one pick stays on the widget.
    static let slotLength: TimeInterval = 3 * 60 * 60

    /// The seed "Spin again" changes. Stored as an Int bit pattern (UserDefaults has no UInt64).
    static var seed: UInt64 {
        get { UInt64(bitPattern: Int64(SharedDefaults.store.integer(forKey: seedKey))) }
        set { SharedDefaults.store.set(Int(Int64(bitPattern: newValue)), forKey: seedKey) }
    }

    /// The 3-hour slot a date falls in.
    static func slot(for date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 / slotLength).rounded(.down))
    }

    /// Start of the slot after the one `date` is in.
    static func nextSlotStart(after date: Date) -> Date {
        Date(timeIntervalSince1970: Double(slot(for: date) + 1) * slotLength)
    }

    /// Favorites first; if none pass the rules, Want to Try; then Nearby.
    static func pool() -> (places: [Place], source: Source)? {
        let rules = SharedCache.pickRules()
        let lists: [(Source, () -> [Place])] = [
            (.favorites, SharedCache.loadFavorites),
            (.interested, SharedCache.loadInterested),
            (.nearby, SharedCache.loadNearby)
        ]
        for (source, load) in lists {
            let eligible = Randomizer.eligible(load(), rules: rules)
            if !eligible.isEmpty { return (eligible, source) }
        }
        return nil
    }

    /// The pick for `date` with the given seed (the stored seed by default).
    static func pick(at date: Date, seed: UInt64 = WidgetPick.seed) -> Result? {
        guard let pool = pool() else { return nil }
        // Sort so the pick doesn't depend on the order the app happened to save the cache in.
        let places = pool.places.sorted { $0.id < $1.id }
        var generator = SeededGenerator(seed: seed ^ (UInt64(bitPattern: slot(for: date)) &* 0x9E37_79B9_7F4A_7C15))
        guard let place = places.randomElement(using: &generator) else { return nil }
        return Result(place: place, source: pool.source)
    }
}

/// SplitMix64: a tiny seeded generator, so the same seed and slot always give the same pick.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
