import SwiftUI

/// Which city the saved lists show.
enum CityFilter: Hashable {
    /// Whatever city you're searching in right now (follows you around).
    case here
    case all
    case city(String)
}

/// "📍 Lexington, KY ▾" drop-down for filtering Favorites and Interested by city.
struct CityMenu: View {
    @Environment(AppModel.self) private var model
    /// Every city on the list being shown, with how many places are in each.
    let cityCounts: [CityCount]

    var body: some View {
        Menu {
            Button {
                model.listCity = .here
            } label: {
                Label(model.currentCity.map { "Here · \($0)" } ?? "Here", systemImage: "location")
            }
            Button {
                model.listCity = .all
            } label: {
                Label("All cities", systemImage: "globe.americas")
            }
            if !cityCounts.isEmpty {
                Divider()
                ForEach(cityCounts, id: \.city) { entry in
                    Button {
                        model.listCity = .city(entry.city)
                    } label: {
                        Text("\(entry.city) (\(entry.count))")
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
        .accessibilityLabel("City: \(title)")
    }

    private var title: String {
        switch model.listCity {
        case .here: return model.currentCity ?? "Here"
        case .all: return "All cities"
        case .city(let name): return name
        }
    }
}

struct CityCount: Hashable {
    let city: String
    let count: Int
}

struct CityGroup {
    let city: String
    let items: [SavedPlace]
}

extension Array where Element == SavedPlace {
    /// Cities on this list, most places first, then A–Z.
    var cityCounts: [CityCount] {
        let counts = Dictionary(grouping: filter { !$0.city.isEmpty }, by: \.city).mapValues(\.count)
        return counts.map { CityCount(city: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.city < $1.city }
    }

    /// One group per city, biggest first. Places still being looked up go last.
    var groupedByCity: [CityGroup] {
        let groups = Dictionary(grouping: self) { $0.city }
        return groups.map { CityGroup(city: $0.key.isEmpty ? "Finding city…" : $0.key, items: $0.value) }
            .sorted { a, b in
                if a.items.first?.city.isEmpty == true { return false }
                if b.items.first?.city.isEmpty == true { return true }
                return a.items.count != b.items.count ? a.items.count > b.items.count : a.city < b.city
            }
    }

    /// Only the places in `city`; all of them when `city` is nil.
    func inCity(_ city: String?) -> [SavedPlace] {
        guard let city else { return self }
        return filter { $0.city == city }
    }
}
