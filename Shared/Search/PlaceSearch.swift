import Foundation
import MapKit
import PickerCore

/// Anything that can find restaurants. The app uses MapKit; previews and
/// tests can swap in a fake.
protocol PlaceSearching: Sendable {
    func search(near center: CLLocationCoordinate2D,
                radiusMeters: Double,
                cuisine: CuisineFilter,
                diet: DietFilter) async throws -> [Place]

    /// Free-text search ("Sora Ramen", "tacos", "brunch") around a point.
    func search(text: String,
                near center: CLLocationCoordinate2D,
                radiusMeters: Double) async throws -> [Place]

    /// Several cuisines at once (empty = "All"), merged, nearest first.
    func search(near center: CLLocationCoordinate2D,
                radiusMeters: Double,
                cuisines: Set<CuisineFilter>,
                diet: DietFilter) async throws -> [Place]
}

extension PlaceSearching {
    func search(near center: CLLocationCoordinate2D,
                radiusMeters: Double,
                cuisine: CuisineFilter) async throws -> [Place] {
        try await search(near: center, radiusMeters: radiusMeters, cuisine: cuisine, diet: .none)
    }

    func search(near center: CLLocationCoordinate2D,
                radiusMeters: Double,
                cuisines: Set<CuisineFilter>) async throws -> [Place] {
        try await search(near: center, radiusMeters: radiusMeters, cuisines: cuisines, diet: .none)
    }

    /// Default: searches each cuisine at once and merges the results (nearest first).
    /// An empty selection means "All". The diet applies to every cuisine.
    func search(near center: CLLocationCoordinate2D,
                radiusMeters: Double,
                cuisines: Set<CuisineFilter>,
                diet: DietFilter) async throws -> [Place] {
        let list = CuisineFilter.ordered(cuisines)
        if list.count == 1 {
            return try await search(near: center, radiusMeters: radiusMeters, cuisine: list[0], diet: diet)
        }
        let batches = try await withThrowingTaskGroup(of: (Int, [Place]?).self) { group in
            for (index, cuisine) in list.enumerated() {
                group.addTask {
                    // One cuisine failing shouldn't sink the others.
                    let places = try? await self.search(near: center, radiusMeters: radiusMeters,
                                                        cuisine: cuisine, diet: diet)
                    return (index, places)
                }
            }
            var results = [(Int, [Place]?)]()
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        if batches.allSatisfy({ $0 == nil }) { throw URLError(.cannotLoadFromNetwork) }

        var seen = Set<String>()
        return batches
            .compactMap { $0 }
            .flatMap { $0 }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }
}

/// Searches Apple Maps data with MapKit. Free, with no API key.
///
/// Apple returns only about two dozen places per search, and with a plain
/// "restaurant" search it leans toward sit-down places, so nearby chains
/// (McDonald's, Burger King) often don't make the cut. To get a fuller list
/// we run several searches at once and merge them:
/// - **By type:** "restaurant" plus fast food, burgers, pizza, and a few more,
///   and Apple's category lookup (finds places by category, not by words).
/// - **By area:** at 3 miles and up, the circle is also split into smaller
///   boxes (a 2×2 grid, or 3×3 at 8+ miles), each with its own search, so
///   the far side of town isn't crowded out by what's closest.
/// About 9–17 searches per refresh, which stays well under Apple's rate
/// limit. Results are kept for a few minutes, so shrinking the radius
/// filters what we have instead of searching again.
///
/// MapKit has no opening hours, photos, or menus; we link to the
/// restaurant's website instead.
struct MapKitPlaceSearch: PlaceSearching {

    /// Extra searches that bring back what "restaurant" leaves out. The label
    /// becomes the place's type when Apple's category is just "restaurant".
    static let typeQueries: [(query: String, label: String)] = [
        ("burgers", "Burgers"),
        ("pizza", "Pizza"),
        ("mexican food", "Mexican"),
        ("chinese food", "Chinese"),
        ("sandwiches", "Sandwiches"),
        ("chicken", "Chicken"),
        // Last, so a place that matches a cuisine too is labeled by its cuisine;
        // known chains are still caught by name for "No fast food".
        ("fast food", "Fast food")
    ]

    static let foodCategories: [MKPointOfInterestCategory] = [
        .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket
    ]

    func search(near center: CLLocationCoordinate2D,
                radiusMeters: Double,
                cuisine: CuisineFilter,
                diet: DietFilter) async throws -> [Place] {
        try await search(near: center, radiusMeters: radiusMeters, cuisines: cuisine == .all ? [] : [cuisine], diet: diet)
    }

    func search(near center: CLLocationCoordinate2D,
                radiusMeters: Double,
                cuisines: Set<CuisineFilter>,
                diet: DietFilter) async throws -> [Place] {
        let key = SearchCache.key(center: center, cuisines: cuisines, diet: diet)
        if let cached = await SearchCache.shared.places(for: key, radiusMeters: radiusMeters) {
            return cached
        }

        let list = CuisineFilter.ordered(cuisines).filter { $0 != .all }
        let boxes = Self.boxes(center: center, radiusMeters: radiusMeters)
        let outer = Array(boxes.dropFirst())
        let whole = boxes[0]
        var jobs: [Job] = []

        if list.isEmpty && diet == .none {
            // "All": by type in the whole circle, plus "restaurant" in each outer box.
            jobs.append(Job(query: "restaurant", region: whole, cuisine: .all, diet: .none))
            jobs.append(Job(query: nil, region: whole, cuisine: .all, diet: .none))
            for type in Self.typeQueries {
                jobs.append(Job(query: type.query, region: whole, cuisine: .all, diet: .none, label: type.label))
            }
            for box in outer {
                jobs.append(Job(query: "restaurant", region: box, cuisine: .all, diet: .none))
            }
        } else {
            // Cuisines and/or a diet: one search each in the whole circle, and
            // in each outer box too unless that would mean too many searches.
            let cuisinesToSearch = list.isEmpty ? [CuisineFilter.all] : list
            let useGrid = cuisinesToSearch.count * boxes.count <= 18
            for cuisine in cuisinesToSearch {
                for box in useGrid ? boxes : [whole] {
                    jobs.append(Job(query: diet.query(for: cuisine), region: box, cuisine: cuisine, diet: diet))
                }
            }
        }

        // MapKit throttles at about 50 searches a minute per app. Slider drags,
        // chip taps, and pickers add up fast (a 10-mile "All" search is 17), so
        // when the budget runs low, keep the whole-circle searches and drop
        // grid boxes. A trimmed list isn't cached, so the next search fills it in.
        try Task.checkCancellation()
        let granted = await SearchCache.shared.reserve(jobs.count, minimum: min(jobs.count, 2))
        let trimmed = granted < jobs.count
        if trimmed {
            let isWhole = { (job: Job) in
                job.region.center.latitude == whole.center.latitude
                    && job.region.center.longitude == whole.center.longitude
            }
            jobs = Array((jobs.filter(isWhole) + jobs.filter { !isWhole($0) }).prefix(granted))
        }

        let batches = await withTaskGroup(of: (Int, [Place]?).self) { group in
            for (index, job) in jobs.enumerated() {
                group.addTask {
                    // One search failing (or being throttled) shouldn't sink the rest.
                    let places = try? await self.run(job, center: center, radiusMeters: radiusMeters)
                    return (index, places)
                }
            }
            var results: [(Int, [Place]?)] = []
            for await batch in group { results.append(batch) }
            // Job order, not finish order, so merge picks the same type every time.
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        if batches.allSatisfy({ $0 == nil }) {
            try Task.checkCancellation()
            throw URLError(.cannotLoadFromNetwork)
        }

        let merged = Self.merge(batches.compactMap { $0 })
        // Don't keep a partial list (some searches failed, were throttled, or
        // were skipped for the budget) for 10 minutes. A complete one is kept
        // even if the caller moved on, so those searches aren't wasted.
        if !trimmed && !batches.contains(where: { $0 == nil }) {
            await SearchCache.shared.store(merged, for: key, radiusMeters: radiusMeters)
        }
        try Task.checkCancellation()
        return merged
    }

    func search(text: String,
                near center: CLLocationCoordinate2D,
                radiusMeters: Double) async throws -> [Place] {
        // A name search shouldn't miss a place just outside the circle,
        // so results aren't trimmed to the radius (MapKit still favors the area).
        let region = MKCoordinateRegion(center: center,
                                        latitudinalMeters: radiusMeters * 2,
                                        longitudinalMeters: radiusMeters * 2)
        _ = await SearchCache.shared.reserve(1)  // counts toward the per-minute budget
        return try await run(Job(query: text, region: region, cuisine: .all, diet: .none, trim: false),
                             center: center, radiusMeters: radiusMeters)
    }

    // MARK: Pieces

    /// One search: a phrase (or Apple's category lookup when `query` is nil) in one box.
    struct Job: Sendable {
        var query: String?
        var region: MKCoordinateRegion
        var cuisine: CuisineFilter
        var diet: DietFilter
        var label: String? = nil
        var trim = true
    }

    /// The whole circle's box first, then the smaller boxes covering it:
    /// none under 3 miles, a 2×2 grid up to 8 miles, a 3×3 grid beyond.
    static func boxes(center: CLLocationCoordinate2D, radiusMeters: Double) -> [MKCoordinateRegion] {
        let whole = MKCoordinateRegion(center: center,
                                       latitudinalMeters: radiusMeters * 2,
                                       longitudinalMeters: radiusMeters * 2)
        let miles = radiusMeters / Place.metersPerMile
        guard miles >= 2.9 else { return [whole] }
        let side = miles >= 7.9 ? 3 : 2
        let cell = radiusMeters * 2 / Double(side)          // each box's width, in meters
        let metersPerDegreeLat = 111_000.0
        let metersPerDegreeLon = max(1, 111_000.0 * cos(center.latitude * .pi / 180))
        var regions = [whole]
        for row in 0..<side {
            for column in 0..<side {
                // Offset of this box's middle from the center, in meters.
                let north = radiusMeters - cell * (Double(row) + 0.5)
                let east = -radiusMeters + cell * (Double(column) + 0.5)
                if side == 3 && row == 1 && column == 1 { continue }  // the middle is the "whole" search's best area
                let middle = CLLocationCoordinate2D(latitude: center.latitude + north / metersPerDegreeLat,
                                                    longitude: center.longitude + east / metersPerDegreeLon)
                // A little bigger than the cell, so places on the edges aren't missed.
                regions.append(MKCoordinateRegion(center: middle,
                                                  latitudinalMeters: cell * 1.15,
                                                  longitudinalMeters: cell * 1.15))
            }
        }
        return regions
    }

    private func run(_ job: Job, center: CLLocationCoordinate2D, radiusMeters: Double) async throws -> [Place] {
        let items: [MKMapItem]
        if let query = job.query {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: Self.foodCategories)
            request.region = job.region
            items = try await MKLocalSearch(request: request).start().mapItems
        } else {
            // Apple's category lookup: places by category, not by matching words.
            let request = MKLocalPointsOfInterestRequest(center: job.region.center,
                                                         radius: min(radiusMeters, 20_000))
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: Self.foodCategories)
            items = try await MKLocalSearch(request: request).start().mapItems
        }

        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return items.compactMap { item -> Place? in
            guard let name = item.name, let location = item.placemark.location else { return nil }
            let distance = origin.distance(from: location)
            // Boxes are squares; keep only what's inside the circle you chose.
            if job.trim && distance > radiusMeters { return nil }
            return Place(
                name: name,
                category: Self.categoryName(for: item, job: job),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                distanceMeters: distance,
                phoneNumber: item.phoneNumber,
                websiteURL: item.url,
                address: item.placemark.title
            )
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    /// Merges batches: one entry per place (same name within ~60 m counts as
    /// the same place), keeping the most specific type, nearest first.
    static func merge(_ batches: [[Place]]) -> [Place] {
        var byID: [String: Place] = [:]
        var order: [String] = []
        var byName: [String: [String]] = [:]   // lowercased name → ids, to catch tiny coordinate differences
        for place in batches.flatMap({ $0 }) {
            let name = place.name.lowercased()
            let here = CLLocation(latitude: place.latitude, longitude: place.longitude)
            var match: String? = byID[place.id] != nil ? place.id : nil
            if match == nil {
                match = byName[name]?.first { id in
                    guard let other = byID[id] else { return false }
                    return CLLocation(latitude: other.latitude, longitude: other.longitude).distance(from: here) < 60
                }
            }
            if let match, let existing = byID[match] {
                if Self.genericTypes.contains(existing.category) && !Self.genericTypes.contains(place.category) {
                    byID[match] = existing.withCategory(place.category)
                }
            } else {
                byID[place.id] = place
                order.append(place.id)
                byName[name, default: []].append(place.id)
            }
        }
        return order.compactMap { byID[$0] }.sorted { $0.distanceMeters < $1.distanceMeters }
    }

    private static let genericTypes: Set<String> = ["Restaurant"]

    /// MapKit has no cuisine data, so we use the cuisine chip or the type
    /// search that found it; otherwise MapKit's broad category.
    private static func categoryName(for item: MKMapItem, job: Job) -> String {
        if job.cuisine != .all { return job.cuisine.label }
        if job.diet != .none { return job.diet.label }
        switch item.pointOfInterestCategory {
        case .cafe?: return "Café"
        case .bakery?: return "Bakery"
        case .brewery?: return "Brewery"
        case .winery?: return "Winery"
        case .foodMarket?: return "Market"
        default: return job.label ?? "Restaurant"
        }
    }
}

private extension Place {
    func withCategory(_ category: String) -> Place {
        Place(id: id, name: name, category: category, latitude: latitude, longitude: longitude,
              distanceMeters: distanceMeters, phoneNumber: phoneNumber, websiteURL: websiteURL,
              address: address)
    }
}

/// The last few nearby searches, so moving the radius slider down (or coming
/// back to the same spot) doesn't search again. Kept for 10 minutes.
actor SearchCache {
    static let shared = SearchCache()

    private struct Entry {
        let radiusMeters: Double
        let places: [Place]
        let savedAt: Date
    }
    private var entries: [String: Entry] = [:]

    /// Same filters, and a center within about 50 m.
    static func key(center: CLLocationCoordinate2D, cuisines: Set<CuisineFilter>, diet: DietFilter) -> String {
        let lat = (center.latitude * 2000).rounded() / 2000
        let lon = (center.longitude * 2000).rounded() / 2000
        let kinds = CuisineFilter.ordered(cuisines).map(\.rawValue).joined(separator: ",")
        return "\(lat)|\(lon)|\(kinds)|\(diet.rawValue)"
    }

    /// Cached places within `radiusMeters`, if we recently searched at least that
    /// far but not more than twice as far (a much wider search spreads its
    /// ~two dozen results per request thin, so it has fewer nearby places than
    /// a search of the smaller circle would).
    func places(for key: String, radiusMeters: Double) -> [Place]? {
        guard let entry = entries[key],
              entry.radiusMeters >= radiusMeters,
              entry.radiusMeters <= radiusMeters * 2,
              -entry.savedAt.timeIntervalSinceNow < 600 else { return nil }
        return entry.places.filter { $0.distanceMeters <= radiusMeters }
    }

    func store(_ places: [Place], for key: String, radiusMeters: Double) {
        entries[key] = Entry(radiusMeters: radiusMeters, places: places, savedAt: Date())
        if entries.count > 12, let oldest = entries.min(by: { $0.value.savedAt.timeIntervalSince($1.value.savedAt) < 0 }) {
            entries[oldest.key] = nil
        }
    }

    /// Pull to refresh: search again for real.
    func clear() { entries = [:] }

    // MARK: Request budget

    /// When recent MapKit searches went out (this process only).
    private var sentAt: [Date] = []
    /// A little under Apple's ~50 a minute, to leave room for name searches.
    private static let perMinute = 44

    /// How many of `wanted` searches may go out now (never fewer than `minimum`).
    /// Records them as sent.
    func reserve(_ wanted: Int, minimum: Int = 1) -> Int {
        let now = Date()
        sentAt.removeAll { now.timeIntervalSince($0) >= 60 }
        let granted = min(wanted, max(minimum, Self.perMinute - sentAt.count))
        sentAt.append(contentsOf: repeatElement(now, count: max(0, granted)))
        return granted
    }
}
