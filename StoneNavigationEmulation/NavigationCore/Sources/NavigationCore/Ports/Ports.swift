import Foundation

/// Джерело часу. У тестах FakeClock, щоб розрахункова позиція рухалась детерміновано.
public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// Джерело геолокації (CLLocationManager або фейк).
@MainActor
public protocol LocationSource: AnyObject {
    var onEvent: (@MainActor (LocationEvent) -> Void)? { get set }
    func start()
    func stop()
}

/// Датчики руху: стоянка чи їзда і кутова швидкість навколо вертикалі.
@MainActor
public protocol MotionSource: AnyObject {
    var onActivity: (@MainActor (MotionActivity) -> Void)? { get set }
    var onYawRate: (@MainActor (YawSample) -> Void)? { get set }
    func start()
    func stop()
}

public enum RouteProviderError: Error, Equatable, Sendable {
    case throttled(retryAfter: TimeInterval?)
    case noRoute
    case failed(String)
}

/// Автомобільний маршрут від постачальника (MapKit зараз, Google пізніше).
@MainActor
public protocol RouteProvider: AnyObject {
    func route(from origin: Coordinate, to destination: Coordinate, via stops: [Coordinate]) async throws -> Route
}

public enum PlaceSearchError: Error, Equatable, Sendable {
    case throttled(retryAfter: TimeInterval?)
    case notFound
    /// Місце в Росії або Білорусі: такі адреси вимкнено.
    case blockedCountry
    case failed(String)
}

/// Пошук місць і орієнтирів.
@MainActor
public protocol PlaceSearch: AnyObject {
    func suggestions(for query: String, near: Coordinate?) async throws -> [PlaceSuggestion]
    func resolve(_ suggestion: PlaceSuggestion) async throws -> Place
    func pointsOfInterest(in region: GeoRegion, categories: Set<PlaceCategory>) async throws -> [PlaceCandidate]
}

/// Голосові підказки.
@MainActor
public protocol SpeechOutput: AnyObject {
    var isVoiceAvailable: Bool { get }
    func speak(_ text: String)
    func stop()
}

/// Журнал переходів режимів (os.Logger, категорія Mode).
public protocol ModeLog: Sendable {
    func log(_ message: String)
}

/// Збереження стану між запусками.
@MainActor
public protocol SessionStore: AnyObject {
    func load() -> SessionSnapshot?
    func save(_ snapshot: SessionSnapshot)
    func clear()
}

/// Усі зовнішні залежності сесії.
@MainActor
public struct NavigationPorts {
    public var location: any LocationSource
    public var motion: any MotionSource
    public var routes: any RouteProvider
    public var places: any PlaceSearch
    public var speech: any SpeechOutput
    public var clock: any Clock
    public var log: any ModeLog
    public var store: any SessionStore

    public init(
        location: any LocationSource,
        motion: any MotionSource,
        routes: any RouteProvider,
        places: any PlaceSearch,
        speech: any SpeechOutput,
        clock: any Clock,
        log: any ModeLog,
        store: any SessionStore
    ) {
        self.location = location
        self.motion = motion
        self.routes = routes
        self.places = places
        self.speech = speech
        self.clock = clock
        self.log = log
        self.store = store
    }
}
