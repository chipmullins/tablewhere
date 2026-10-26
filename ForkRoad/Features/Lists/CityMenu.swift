import SwiftUI
import CoreLocation

/// Which metro area the saved lists show.
enum CityFilter: Hashable {
    /// The metro you're searching in right now (follows you around).
    case here
    case all
    /// A metro, by its name (its biggest city, e.g. "Lexington, KY").
    case metro(String)
}

/// A metro area built from your saved places: nearby cities grouped under the
/// one with the most saves. Lexington, Nicholasville, and Georgetown all
/// become "Lexington, KY area".
struct Metro: Identifiable {
    /// Cities within this distance of a metro's main city join that metro.
    static let radiusMeters = 25 * 1609.344
    static let pendingName = "Finding city…"

    let name: String
    var cities: [String]
    let latitude: Double
    let longitude: Double
    var items: [SavedPlace]

    var id: String { name }
    var isPending: Bool { name == Metro.pendingName }

    /// "Lexington, KY area" when it spans several cities, else just the city.
    var label: String { cities.count > 1 ? "\(name) area" : name }

    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        !isPending && distance(to: coordinate) <= Metro.radiusMeters
    }
}

extension Array where Element == SavedPlace {
    /// Saved places grouped into metro areas, most places first.
    var metros: [Metro] {
        // 1. Each city's center, biggest cities first so they anchor their metro.
        let byCity = Dictionary(grouping: filter { !$0.city.isEmpty }, by: \.city)
        let cities = byCity.map { city, items -> (city: String, items: [SavedPlace], center: CLLocationCoordinate2D) in
            let lat = items.map(\.latitude).reduce(0, +) / Double(items.count)
            let lon = items.map(\.longitude).reduce(0, +) / Double(items.count)
            return (city, items, CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        .sorted { $0.items.count != $1.items.count ? $0.items.count > $1.items.count : $0.city < $1.city }

        // 2. Join each city to the nearest existing metro in range, or start a new one.
        var metros: [Metro] = []
        for entry in cities {
            let match = metros.indices
                .filter { metros[$0].distance(to: entry.center) <= Metro.radiusMeters }
                .min { metros[$0].distance(to: entry.center) < metros[$1].distance(to: entry.center) }
            if let index = match {
                metros[index].cities.append(entry.city)
                metros[index].items += entry.items
            } else {
                metros.append(Metro(name: entry.city, cities: [entry.city],
                                    latitude: entry.center.latitude, longitude: entry.center.longitude,
                                    items: entry.items))
            }
        }

        // 3. Places whose city is still being looked up join the metro they're in.
        var pending: [SavedPlace] = []
        for item in self where item.city.isEmpty {
            let spot = CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
            if let index = metros.firstIndex(where: { $0.contains(spot) }) {
                metros[index].items.append(item)
            } else {
                pending.append(item)
            }
        }

        var result = metros.sorted { $0.items.count != $1.items.count ? $0.items.count > $1.items.count : $0.name < $1.name }
        if let first = pending.first {
            result.append(Metro(name: Metro.pendingName, cities: [], latitude: first.latitude,
                                longitude: first.longitude, items: pending))
        }
        return result
    }

    /// The places a filter shows. "Here" is the metro containing `center`.
    func filtered(by filter: CityFilter, near center: CLLocationCoordinate2D) -> [SavedPlace] {
        switch filter {
        case .all: return self
        case .metro(let name): return metros.first { $0.name == name }?.items ?? []
        case .here: return metros.first { $0.contains(center) }?.items ?? []
        }
    }
}

/// "📍 Lexington, KY area ▾" drop-down for filtering Favorites and Interested by metro.
struct CityMenu: View {
    @Environment(AppModel.self) private var model
    /// Metros on the list being shown.
    let metros: [Metro]

    var body: some View {
        Menu {
            Button {
                model.listCity = .here
            } label: {
                Label("Here · \(hereLabel)", systemImage: "location")
            }
            Button {
                model.listCity = .all
            } label: {
                Label("All areas", systemImage: "globe.americas")
            }
            let named = metros.filter { !$0.isPending }
            if !named.isEmpty {
                Divider()
                ForEach(named) { metro in
                    Button {
                        model.listCity = .metro(metro.name)
                    } label: {
                        Text("\(metro.label) (\(metro.items.count))")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.listCity == .all ? "globe.americas" : "mappin")
                    .foregroundStyle(Theme.saffron)
                Text(title).lineLimit(1)
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
        .accessibilityLabel("Area: \(title)")
    }

    /// The metro you're in, else your current city.
    private var hereLabel: String {
        metros.first { $0.contains(model.center) }?.label ?? model.currentCity ?? "Near you"
    }

    private var title: String {
        switch model.listCity {
        case .here: return hereLabel
        case .all: return "All areas"
        case .metro(let name): return metros.first { $0.name == name }?.label ?? name
        }
    }
}
