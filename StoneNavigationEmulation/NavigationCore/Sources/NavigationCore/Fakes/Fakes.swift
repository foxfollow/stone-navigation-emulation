import Foundation

/// Годинник, яким керує тест.
public final class FakeClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = now
    }

    public var now: Date { lock.withLock { current } }

    public func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }

    public func set(_ date: Date) {
        lock.withLock { current = date }
    }
}

/// Геолокація, події якої тест надсилає вручну.
@MainActor
public final class FakeLocationSource: LocationSource {
    public var onEvent: (@MainActor (LocationEvent) -> Void)?
    public private(set) var isRunning = false

    public init() {}

    public func start() { isRunning = true }
    public func stop() { isRunning = false }

    public func send(_ event: LocationEvent) {
        onEvent?(event)
    }
}

@MainActor
public final class FakeMotionSource: MotionSource {
    public var onActivity: (@MainActor (MotionActivity) -> Void)?
    public var onYawRate: (@MainActor (YawSample) -> Void)?
    public private(set) var isRunning = false

    public init() {}

    public func start() { isRunning = true }
    public func stop() { isRunning = false }

    public func send(_ activity: MotionActivity) { onActivity?(activity) }
    public func send(_ sample: YawSample) { onYawRate?(sample) }
}

@MainActor
public final class FakeRouteProvider: RouteProvider {
    public struct Request: Equatable, Sendable {
        public let origin: Coordinate
        public let destination: Coordinate
        public let stops: [Coordinate]
    }

    public var result: Result<Route, RouteProviderError>
    public private(set) var requests: [Request] = []

    public init(result: Result<Route, RouteProviderError>) {
        self.result = result
    }

    public func route(from origin: Coordinate, to destination: Coordinate, via stops: [Coordinate]) async throws -> Route {
        requests.append(Request(origin: origin, destination: destination, stops: stops))
        return try result.get()
    }
}

/// Пошук на записаних даних: POI з фікстури, підказки зі списку.
@MainActor
public final class FakePlaceSearch: PlaceSearch {
    public var candidates: [PlaceCandidate]
    public var places: [Place]
    public var error: PlaceSearchError?
    public private(set) var poiRequests: [GeoRegion] = []
    /// Які типи просили в кожному запиті орієнтирів.
    public private(set) var poiCategories: [Set<PlaceCategory>] = []
    /// Як MapKit: на один запит не більше стількох місць, ближчих до центру регіону.
    public var maxResults: Int?
    /// З якого за ліком запиту орієнтирів (від 1) кидати `error`; nil означає з першого.
    public var errorFromRequest: Int?

    public init(candidates: [PlaceCandidate] = [], places: [Place] = [], maxResults: Int? = nil) {
        self.candidates = candidates
        self.places = places
        self.maxResults = maxResults
    }

    public func suggestions(for query: String, near: Coordinate?) async throws -> [PlaceSuggestion] {
        let needle = query.lowercased()
        return places.enumerated()
            .filter { !needle.isEmpty && $0.element.name.lowercased().contains(needle) }
            .map { PlaceSuggestion(id: String($0.offset), title: $0.element.name, subtitle: $0.element.subtitle ?? "") }
    }

    public func resolve(_ suggestion: PlaceSuggestion) async throws -> Place {
        guard let index = Int(suggestion.id), places.indices.contains(index) else { throw PlaceSearchError.notFound }
        return places[index]
    }

    public func pointsOfInterest(in region: GeoRegion, categories: Set<PlaceCategory>) async throws -> [PlaceCandidate] {
        poiRequests.append(region)
        poiCategories.append(categories)
        if let error, poiRequests.count >= errorFromRequest ?? 1 { throw error }
        let found = candidates.filter { region.contains($0.coordinate) && categories.contains($0.category) }
        guard let maxResults else { return found }
        let center = region.center
        return Array(found.sorted { Geo.distance($0.coordinate, center) < Geo.distance($1.coordinate, center) }.prefix(maxResults))
    }
}

@MainActor
public final class FakeSpeechOutput: SpeechOutput {
    public var isVoiceAvailable: Bool
    public private(set) var spoken: [String] = []

    public init(isVoiceAvailable: Bool = true) {
        self.isVoiceAvailable = isVoiceAvailable
    }

    public func speak(_ text: String) { spoken.append(text) }
    public func stop() {}
}

public final class RecordingModeLog: ModeLog, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    public init() {}

    public var messages: [String] { lock.withLock { storage } }

    public func log(_ message: String) {
        lock.withLock { storage.append(message) }
    }
}

/// Журнал, який нічого не пише (сценарії без os.Logger не потрібні: там теж пишемо в OSModeLog).
public struct SilentModeLog: ModeLog {
    public init() {}
    public func log(_ message: String) {}
}

@MainActor
public final class InMemorySessionStore: SessionStore {
    public private(set) var snapshot: SessionSnapshot?
    public private(set) var saveCount = 0

    public init(snapshot: SessionSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func load() -> SessionSnapshot? { snapshot }

    public func save(_ snapshot: SessionSnapshot) {
        self.snapshot = snapshot
        saveCount += 1
    }

    public func clear() { snapshot = nil }
}
