import Foundation

/// Стан, що переживає перезапуск: маршрут із кроками й polyline, позиція, орієнтири, кеш.
public struct SessionSnapshot: Codable, Sendable, Equatable {
    public var version = 1
    public var route: Route?
    public var destination: Place?
    public var stops: [Coordinate]
    public var along: Double
    public var isNavigating: Bool
    public var reckoner: DeadReckoner
    public var landmarkCandidates: [PlaceCandidate]
    public var routeCache: RouteCache
    public var savedAt: Date

    public init(
        route: Route?,
        destination: Place?,
        stops: [Coordinate],
        along: Double,
        isNavigating: Bool,
        reckoner: DeadReckoner,
        landmarkCandidates: [PlaceCandidate],
        routeCache: RouteCache,
        savedAt: Date
    ) {
        self.route = route
        self.destination = destination
        self.stops = stops
        self.along = along
        self.isNavigating = isNavigating
        self.reckoner = reckoner
        self.landmarkCandidates = landmarkCandidates
        self.routeCache = routeCache
        self.savedAt = savedAt
    }
}
