import Foundation

/// Ключ кешу: координати округлено до 0,001° (≈100 м), щоб дрібні зсуви не вимагали нового запиту.
public struct RouteRequestKey: Codable, Hashable, Sendable {
    public let origin: Coordinate
    public let destination: Coordinate
    public let stops: [Coordinate]

    public init(origin: Coordinate, destination: Coordinate, stops: [Coordinate] = []) {
        self.origin = Self.round(origin)
        self.destination = Self.round(destination)
        self.stops = stops.map(Self.round)
    }

    static func round(_ coordinate: Coordinate) -> Coordinate {
        Coordinate(latitude: (coordinate.latitude * 1000).rounded() / 1000,
                   longitude: (coordinate.longitude * 1000).rounded() / 1000)
    }
}

/// Кеш відповідей постачальника маршрутів, щоб не перебудовувати маршрут без потреби.
public struct RouteCache: Codable, Sendable, Equatable {
    public static let maxAge: TimeInterval = 12 * 3600
    public static let capacity = 10

    struct Entry: Codable, Sendable, Equatable {
        let key: RouteRequestKey
        let route: Route
        let storedAt: Date
    }

    private var entries: [Entry] = []

    public init() {}

    public var count: Int { entries.count }

    public func route(for key: RouteRequestKey, now: Date) -> Route? {
        entries.last { $0.key == key && now.timeIntervalSince($0.storedAt) <= Self.maxAge }?.route
    }

    public mutating func store(_ route: Route, for key: RouteRequestKey, at now: Date) {
        entries.removeAll { $0.key == key }
        entries.append(Entry(key: key, route: route, storedAt: now))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }
}
