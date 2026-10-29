import Foundation

/// Збережені адреси: дім, робота, вибрані адреси й останні пункти призначення.
/// Адреси в Росії та Білорусі не зберігаються.
public struct SavedPlaces: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case home, work, favorite, recent

        public var title: String {
            switch self {
            case .home: "Дім"
            case .work: "Робота"
            case .favorite: "Збережене"
            case .recent: "Нещодавнє"
            }
        }

        public var symbolName: String {
            switch self {
            case .home: "house.fill"
            case .work: "briefcase.fill"
            case .favorite: "star.fill"
            case .recent: "clock.arrow.circlepath"
            }
        }
    }

    /// Рядок списку: що це за адреса і де вона лежить (`index` у вибраних чи останніх).
    public struct Entry: Sendable, Equatable, Identifiable {
        public let kind: Kind
        public let place: Place
        public let index: Int

        public var id: String {
            switch kind {
            case .home, .work: "saved.\(kind.rawValue)"
            case .favorite, .recent: "saved.\(kind.rawValue).\(index)"
            }
        }
    }

    public private(set) var home: Place?
    public private(set) var work: Place?
    public private(set) var favorites: [Place] = []
    /// Останні пункти призначення, найновіший перший.
    public private(set) var recents: [Place] = []

    public static let maxRecents = 15
    /// Ближче за це вважаємо тим самим місцем (назва могла прийти іншою мовою).
    public static let samePlaceDistance = 30.0

    public init() {}

    public static func isSame(_ a: Place, _ b: Place) -> Bool {
        Geo.distance(a.coordinate, b.coordinate) <= samePlaceDistance
    }

    /// Зберегти адресу як дім, роботу, вибрану або останню. false, якщо адресу зберігати не можна.
    @discardableResult
    public mutating func store(_ place: Place, as kind: Kind) -> Bool {
        guard !BlockedCountries.contains(code: place.countryCode) else { return false }
        switch kind {
        case .home:
            home = place
        case .work:
            work = place
        case .favorite:
            favorites.removeAll { Self.isSame($0, place) }
            favorites.append(place)
        case .recent:
            recents.removeAll { Self.isSame($0, place) }
            recents.insert(place, at: 0)
            if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
        }
        return true
    }

    public mutating func remove(_ entry: Entry) {
        switch entry.kind {
        case .home: home = nil
        case .work: work = nil
        case .favorite: if favorites.indices.contains(entry.index) { favorites.remove(at: entry.index) }
        case .recent: if recents.indices.contains(entry.index) { recents.remove(at: entry.index) }
        }
    }

    public mutating func clearRecents() {
        recents.removeAll()
    }

    /// Дім, робота і вибрані адреси.
    public var pinned: [Entry] {
        var entries: [Entry] = []
        if let home { entries.append(Entry(kind: .home, place: home, index: 0)) }
        if let work { entries.append(Entry(kind: .work, place: work, index: 0)) }
        entries += favorites.enumerated().map { Entry(kind: .favorite, place: $1, index: $0) }
        return entries
    }

    /// Останні адреси без тих, що вже є серед дому, роботи і вибраних.
    public var recentEntries: [Entry] {
        let pinned = pinned.map(\.place)
        return recents.enumerated()
            .filter { _, place in !pinned.contains { Self.isSame($0, place) } }
            .map { Entry(kind: .recent, place: $1, index: $0) }
    }

    /// Збережені й останні адреси, що підходять під текст пошуку: дім, робота, вибрані, потім останні.
    /// «дім» і «робота» знаходять дім і роботу за назвою.
    public func matching(_ query: String) -> [Entry] {
        let needle = Self.normalize(query)
        guard !needle.isEmpty else { return [] }
        return (pinned + recentEntries).filter { entry in
            [entry.place.name, entry.place.subtitle ?? "", entry.kind == .home || entry.kind == .work ? entry.kind.title : ""]
                .contains { Self.normalize($0).contains(needle) }
        }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Читає і пише збережені адреси в KeyValueStorage одним JSON.
public struct SavedPlacesRepository: Sendable {
    public static let key = "savedPlaces"

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage) {
        self.storage = storage
    }

    public func load() -> SavedPlaces {
        guard let data = storage.data(forKey: Self.key),
              let places = try? JSONDecoder().decode(SavedPlaces.self, from: data) else { return SavedPlaces() }
        return places
    }

    public func save(_ places: SavedPlaces) {
        guard let data = try? JSONEncoder().encode(places) else { return }
        storage.set(data, forKey: Self.key)
    }

    public func clear() {
        storage.removeValue(forKey: Self.key)
    }
}
