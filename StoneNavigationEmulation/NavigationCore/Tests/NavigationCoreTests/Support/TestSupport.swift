import Foundation
import Testing
@testable import NavigationCore

/// Записані фікстури з ресурсів тестів.
enum Fixtures {
    static func url(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }

    static func route() throws -> Route {
        try JSONDecoder().decode(Route.self, from: Data(contentsOf: url("test_route", "json")))
    }

    static func pois() throws -> [PlaceCandidate] {
        try JSONDecoder().decode([PlaceCandidate].self, from: Data(contentsOf: url("test_pois", "json")))
    }

    static func track() throws -> GPXTrack {
        try GPXTrack.parse(Data(contentsOf: url("test_track", "gpx")))
    }
}

/// Синтетичний Г-подібний маршрут із точно відомою геометрією:
/// 1000 м на північ, поворот праворуч, 1000 м на схід. Середня швидкість 10 м/с.
enum TestRoute {
    static let start = Coordinate(latitude: 50.0, longitude: 30.0)
    static let corner = Geo.destination(from: start, bearing: 0, distance: 1000)
    static let end = Geo.destination(from: corner, bearing: 90, distance: 1000)

    static func make(expectedTravelTime: TimeInterval? = 200, id: String = "l-route") -> Route {
        let north = stride(from: 0.0, through: 1000, by: 100).map { Geo.destination(from: start, bearing: 0, distance: $0) }
        let east = stride(from: 100.0, through: 1000, by: 100).map { Geo.destination(from: corner, bearing: 90, distance: $0) }
        return Route(
            id: id,
            name: "Тестова",
            origin: start,
            destination: end,
            coordinates: north + east,
            // Як у MapKit: вказівку виконують у кінці кроку.
            steps: [
                RouteStep(instructions: "", distance: 0, coordinates: [start]),
                RouteStep(instructions: "Поверніть праворуч на вулицю Другу", distance: 1000, coordinates: north),
                RouteStep(instructions: "Пункт призначення праворуч", distance: 1000, coordinates: [corner] + east),
            ],
            distance: 2000,
            expectedTravelTime: expectedTravelTime
        )
    }

    /// Прямий маршрут на північ завдовжки `length` метрів.
    static func straight(length: Double) -> Route {
        let points = stride(from: 0.0, through: length, by: 100).map { Geo.destination(from: start, bearing: 0, distance: $0) }
        return Route(
            id: "straight-\(Int(length))",
            name: "Пряма",
            origin: start,
            destination: points[points.count - 1],
            coordinates: points,
            steps: [
                RouteStep(instructions: "", distance: 0, coordinates: [start]),
                RouteStep(instructions: "Пункт призначення попереду", distance: length, coordinates: points),
            ],
            distance: length,
            expectedTravelTime: length / 12
        )
    }

    /// Маршрут `north` метрів на північ, поворот праворуч (маневр #1), далі `east` метрів на схід (прибуття, #2).
    static func turning(north: Double, east: Double) -> Route {
        let northPoints = stride(from: 0.0, through: north, by: 100).map { Geo.destination(from: start, bearing: 0, distance: $0) }
        let corner = northPoints[northPoints.count - 1]
        let eastPoints = stride(from: 100.0, through: east, by: 100).map { Geo.destination(from: corner, bearing: 90, distance: $0) }
        return Route(
            id: "turning-\(Int(north))-\(Int(east))",
            name: "З поворотом",
            origin: start,
            destination: eastPoints[eastPoints.count - 1],
            coordinates: northPoints + eastPoints,
            steps: [
                RouteStep(instructions: "", distance: 0, coordinates: [start]),
                RouteStep(instructions: "Поверніть праворуч на вулицю Другу", distance: north, coordinates: northPoints),
                RouteStep(instructions: "Пункт призначення праворуч", distance: east, coordinates: [corner] + eastPoints),
            ],
            distance: north + east,
            expectedTravelTime: (north + east) / 10
        )
    }

    /// Точка на маршруті на дистанції `along`, зсунута вбік на `offset` метрів (додатне праворуч).
    static func point(along: Double, offset: Double = 0, route: Route = make()) -> Coordinate {
        let base = route.polyline.coordinate(at: along)
        guard offset != 0 else { return base }
        let bearing = route.polyline.bearing(at: along) + (offset > 0 ? 90 : -90)
        return Geo.destination(from: base, bearing: bearing, distance: abs(offset))
    }
}

extension LocationFix {
    static func good(_ coordinate: Coordinate, at date: Date, accuracy: Double = 5, speed: Double = 10, course: Double = -1) -> LocationFix {
        LocationFix(coordinate: coordinate, horizontalAccuracy: accuracy, speed: speed, course: course, timestamp: date)
    }
}

/// Рушій на синтетичному маршруті з годинником, яким керує тест.
struct EngineHarness {
    var engine: NavigationEngine
    let clock: FakeClock
    let route: Route

    init(settings: NavigationSettings = .standard, route: Route = TestRoute.make(), along: Double = 0) {
        clock = FakeClock()
        self.route = route
        engine = NavigationEngine(settings: settings, now: clock.now)
        engine.setRoute(route, along: along, now: clock.now)
    }

    var now: Date { clock.now }

    /// Добра точка GPS на маршруті.
    mutating func gps(along: Double, offset: Double = 0, accuracy: Double = 5, speed: Double = 10, course: Double = -1) {
        let fix = LocationFix.good(TestRoute.point(along: along, offset: offset, route: route), at: clock.now, accuracy: accuracy, speed: speed, course: course)
        engine.handle(.fix(fix), now: clock.now)
    }

    mutating func send(_ event: LocationEvent) {
        engine.handle(event, now: clock.now)
    }

    mutating func advance(_ seconds: TimeInterval, tick: Bool = true) {
        clock.advance(by: seconds)
        if tick { engine.tick(now: clock.now) }
    }

    /// Увійти в розрахунковий режим через помилку геолокації.
    mutating func loseGPS() {
        send(.error(.locationUnknown))
    }
}

@MainActor
struct SessionHarness {
    let clock = FakeClock()
    let location = FakeLocationSource()
    let motion = FakeMotionSource()
    let routes: FakeRouteProvider
    let places: FakePlaceSearch
    let speech = FakeSpeechOutput()
    let log = RecordingModeLog()
    let store: InMemorySessionStore
    let session: NavigationSession

    init(settings: NavigationSettings = .standard, route: Route = TestRoute.make(), candidates: [PlaceCandidate] = [], store: InMemorySessionStore = InMemorySessionStore()) {
        routes = FakeRouteProvider(result: .success(route))
        places = FakePlaceSearch(candidates: candidates)
        self.store = store
        // Як у додатку: пошук без адрес у Росії та Білорусі.
        session = NavigationSession(
            ports: NavigationPorts(location: location, motion: motion, routes: routes, places: CountryFilteredPlaceSearch(base: places), speech: speech, clock: clock, log: log, store: store),
            settings: settings
        )
        session.startTracking()
    }

    func advance(_ seconds: TimeInterval) {
        clock.advance(by: seconds)
        session.tick()
    }

    func gps(_ coordinate: Coordinate, accuracy: Double = 5, speed: Double = 10) {
        location.send(.fix(.good(coordinate, at: clock.now, accuracy: accuracy, speed: speed)))
    }
}
