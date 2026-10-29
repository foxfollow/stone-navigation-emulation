import Foundation
import Observation

/// Коротке повідомлення для тосту на екрані.
public struct SessionNotice: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let text: String
}

/// Координатор навігації: з'єднує порти (геолокація, датчики, маршрути, пошук, голос, збереження)
/// з чистим рушієм `NavigationEngine`. Екрани читають стан звідси через Environment.
@MainActor
@Observable
public final class NavigationSession {
    public private(set) var engine: NavigationEngine
    public private(set) var settings: NavigationSettings
    /// Час останнього оновлення: від нього рахуються таймер «без GPS» і плавний перехід.
    public private(set) var now: Date
    /// Коли рушій востаннє зрушив позицію: від цієї миті екран веде точку далі зі швидкістю `engine.alongSpeed`.
    public private(set) var alongUpdatedAt: Date
    @ObservationIgnored private var lastAlong = 0.0
    public private(set) var destination: Place?
    public private(set) var stops: [Coordinate] = []
    public private(set) var isNavigating = false
    public private(set) var isRouting = false
    public private(set) var routeError: String?
    /// Усі отримані місця (до фільтра коридору). Не викидаються, коли маршрут перебудовано:
    /// на новому маршруті ті самі місця одразу стають орієнтирами, навіть без мережі.
    public private(set) var landmarkCandidates: [PlaceCandidate] = []
    /// Орієнтири в коридорі маршруту, впорядковані вздовж маршруту.
    public private(set) var landmarks: [Landmark] = []
    /// Як ідуть запити орієнтирів.
    public private(set) var landmarkStatus = LandmarkLoadStatus()
    public private(set) var lastSpokenPhrase: String?
    public private(set) var notice: SessionNotice?
    public private(set) var activity: MotionActivity = .unknown

    @ObservationIgnored private var ports: NavigationPorts
    @ObservationIgnored private var prompter = VoicePrompter()
    /// Для яких ділянок поточного маршруту MapKit уже відповів і на які типи.
    @ObservationIgnored private var landmarkLoaded: [LandmarkArea: Set<PlaceCategory>] = [:]
    /// Вікна, де MapKit віддав повну відповідь: їх запитуємо ще й половинами.
    @ObservationIgnored private var denseWindows = Set<Int>()
    /// Останнє обмеження поставив сам MapKit (а не мережа): ручне «Оновити» його не обходить.
    @ObservationIgnored private var isThrottledByMapKit = false
    @ObservationIgnored private var landmarkTask: Task<Void, Never>?
    @ObservationIgnored public private(set) var routeCache = RouteCache()
    @ObservationIgnored private var routeThrottle = RequestThrottle()
    @ObservationIgnored private var placeThrottle = RequestThrottle()
    @ObservationIgnored private var turnDetector = TurnDetector()
    @ObservationIgnored private var lastPersisted: Date?
    @ObservationIgnored private var lastProgressLog: Date?
    @ObservationIgnored private var isTracking = false
    @ObservationIgnored private var landmarkGeneration = 0
    @ObservationIgnored private var pendingTasks: [UUID: Task<Void, Never>] = [:]

    /// Як часто писати в журнал, що розрахункова точка рухається.
    static let progressLogInterval: TimeInterval = 5
    /// Як часто зберігати стан під час навігації.
    static let persistInterval: TimeInterval = 15
    /// Скільки місць тримати в пам'яті між маршрутами; найстаріші викидаються першими.
    static let maxCandidates = 3000

    public init(ports: NavigationPorts, settings: NavigationSettings, restoreState: Bool = true) {
        let now = ports.clock.now
        self.ports = ports
        self.settings = settings
        self.now = now
        self.alongUpdatedAt = now
        self.engine = NavigationEngine(settings: settings, now: now)
        if restoreState, let snapshot = ports.store.load() {
            restore(from: snapshot)
        }
    }

    // MARK: Похідні дані для екранів

    public var position: Coordinate? { engine.position(at: now) }
    public var heading: Double? { engine.heading(at: now) }
    /// Чи можна перейти на GPS одним тапом, чи треба питати «Все одно вести за GPS?».
    public var gpsAvailability: GPSAvailability { engine.gpsAvailability(at: ports.clock.now) }
    public var isVoiceAvailable: Bool { ports.speech.isVoiceAvailable }
    public var locationSource: any LocationSource { ports.location }
    public var placeSearch: any PlaceSearch { ports.places }

    public var visibleLandmarks: [Landmark] {
        let categories = settings.enabledCategories
        return landmarks.filter { categories.contains($0.place.category) }
    }

    /// Орієнтир біля наступного повороту (з тих, що показують фільтри): за ним видно, де повертати.
    public var nextTurnLandmark: Landmark? {
        guard let maneuver = engine.nextManeuver?.maneuver, maneuver.isTurn else { return nil }
        return LandmarkSelector.nearTurn(visibleLandmarks, maneuver: maneuver)
    }

    /// Орієнтири біля поворотів у межах `distance` метрів попереду: карта показує їх першими.
    public func turnLandmarks(within distance: Double) -> [Landmark] {
        guard let route = engine.route else { return [] }
        let visible = visibleLandmarks
        return route.maneuvers
            .filter { $0.isTurn && $0.along > engine.along && $0.along - engine.along <= distance }
            .compactMap { LandmarkSelector.nearTurn(visible, maneuver: $0) }
    }

    public var estimatedArrival: Date? {
        engine.remainingTime.map { now.addingTimeInterval($0) }
    }

    // MARK: Життєвий цикл

    public func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        attach(ports.location)
        ports.motion.onActivity = { [weak self] activity in self?.receive(activity: activity) }
        ports.motion.onYawRate = { [weak self] sample in self?.receive(yaw: sample) }
        ports.location.start()
        if settings[.motionEnabled] { ports.motion.start() }
    }

    public func stopTracking() {
        isTracking = false
        ports.location.stop()
        ports.motion.stop()
    }

    /// Замінити джерело геолокації (режим тестування з GPX і назад).
    public func replaceLocationSource(_ source: any LocationSource) {
        ports.location.stop()
        ports.location.onEvent = nil
        ports.location = source
        if isTracking {
            attach(source)
            source.start()
        }
    }

    private func attach(_ source: any LocationSource) {
        source.onEvent = { [weak self] event in self?.receive(event) }
    }

    public func apply(settings newSettings: NavigationSettings) {
        let old = settings
        settings = newSettings
        engine.apply(settings: newSettings)
        if old[.landmarkCorridor] != newSettings[.landmarkCorridor] { reselectLandmarks() }
        if old[.motionEnabled] != newSettings[.motionEnabled], isTracking {
            if newSettings[.motionEnabled] { ports.motion.start() } else { ports.motion.stop() }
        }
        if !newSettings[.voiceEnabled] { ports.speech.stop() }
    }

    /// Головний цикл: викликається з частотою `updateInterval`.
    public func tick() {
        now = ports.clock.now
        engine.tick(now: now)
        processEngineEvents()
        guard isNavigating, let route = engine.route else { return }
        speakIfNeeded(route: route)
        loadLandmarksIfNeeded()
        updateLandmarkCoverage(route: route)
        logProgressIfNeeded()
        if lastPersisted.map({ now.timeIntervalSince($0) >= Self.persistInterval }) ?? true {
            persist()
        }
    }

    // MARK: Вхідні події

    public func receive(_ event: LocationEvent) {
        now = ports.clock.now
        engine.handle(event, now: now)
        processEngineEvents()
    }

    public func receive(activity: MotionActivity) {
        self.activity = activity
        changeMotion { $0.handleActivity(activity) }
    }

    public func receive(yaw sample: YawSample) {
        guard settings[.motionEnabled],
              let turn = turnDetector.add(sample, thresholdDegrees: settings[.gyroTurnDegrees]) else { return }
        now = ports.clock.now
        engine.handleTurn(degrees: turn.degrees, now: now)
        processEngineEvents()
    }

    // MARK: Маршрут

    /// Почати навігацію по готовому маршруту (з MapKit, кешу або фікстури).
    /// `startPoint`: маршрут прокладено від вибраної точки, а не від моєї позиції.
    public func begin(route: Route, destination: Place?, stops: [Coordinate] = [], startPoint: Place? = nil) {
        now = ports.clock.now
        let gpsAlong = engine.rawGPSCoordinate.flatMap { route.polyline.project($0)?.along } ?? 0
        engine.setRoute(route, along: startPoint == nil ? gpsAlong : 0, now: now)
        if startPoint != nil { engine.startAtChosenPoint(now: now) }
        self.destination = destination
        self.stops = stops
        isNavigating = true
        routeError = nil
        prompter.reset()
        resetLandmarkLoading()
        // Відомі місця лишаються: на новому маршруті вони одразу стають орієнтирами.
        reselectLandmarks()
        let average = route.averageSpeed.map(UkrainianFormat.speed) ?? "невідома"
        ports.log.log("Навігація: маршрут «\(route.name)», \(Int(route.polyline.length)) м, кроків \(route.steps.count), середня швидкість \(average)")
        processEngineEvents()
        if let startPoint {
            if engine.reckoner.isPaused {
                ports.log.log("Старт із вибраної точки «\(startPoint.name)»: розрахункова позиція на старті, пауза до «Далі»")
                notice = SessionNotice(text: "Старт: \(startPoint.name). Натисніть «Далі», коли рушите")
            } else if engine.control == .manualGPS {
                ports.log.log("Старт із вибраної точки «\(startPoint.name)»: GPS увімкнено вручну, ведемо за GPS")
            } else {
                ports.log.log("Старт із вибраної точки «\(startPoint.name)»: GPS поруч, ведемо за GPS")
            }
        }
        persist()
    }

    public func endNavigation() {
        now = ports.clock.now
        isNavigating = false
        engine.setRoute(nil, now: now)
        destination = nil
        stops = []
        landmarks = []
        resetLandmarkLoading()
        prompter.reset()
        ports.speech.stop()
        ports.log.log("Навігацію завершено")
        persist()
    }

    /// Маршрут до місця: від моєї позиції або, якщо задано `origin`, від вибраної точки відправлення.
    public func buildRoute(to place: Place, from origin: Place? = nil) async {
        if let origin {
            await requestRoute(from: origin.coordinate, to: place, stops: [], startPoint: origin)
        } else {
            await requestRoute(from: position ?? engine.rawGPSCoordinate, to: place, stops: [])
        }
    }

    /// «Перебудувати маршрут від моєї позиції» після відхилення.
    public func rebuildFromCurrentGPS() async {
        guard let destination else { return }
        await requestRoute(from: engine.rawGPSCoordinate ?? position, to: destination, stops: remainingStops())
    }

    /// Наскільки далеко від лінії маршруту може бути точка з довгого тапу, щоб «Я тут» поставив позицію навпроти неї.
    public static let relocateTolerance = 100.0

    /// Де точка з карти відносно маршруту: позиція навпроти неї і відстань від лінії.
    public func routeProjection(of coordinate: Coordinate) -> RouteProjection? {
        engine.route?.polyline.project(coordinate)
    }

    /// «Я тут» з довгого тапу: позиція на маршруті навпроти вибраної точки. Точка далі від лінії, ніж
    /// `relocateTolerance`, не підходить: я не на маршруті, треба «Маршрут звідси». Повертає, чи позицію переставлено.
    @discardableResult
    public func moveHere(_ coordinate: Coordinate) -> Bool {
        guard let projection = routeProjection(of: coordinate), projection.offset <= Self.relocateTolerance else { return false }
        mutate { engine, now in engine.setPosition(along: projection.along, now: now, reason: .mapPoint) }
        return true
    }

    /// «Маршрут звідси»: я звернув не туди і тепер тут. Маршрут від цієї точки до того самого пункту
    /// призначення з тими самими зупинками попереду. Точка, що їхала, їде далі новим маршрутом без паузи.
    public func rebuildRoute(from place: Place) async {
        guard let destination else { return }
        let wasMoving = !engine.reckoner.isPaused
        await requestRoute(from: place.coordinate, to: destination, stops: remainingStops(), startPoint: place)
        guard routeError == nil, wasMoving else { return }
        if engine.reckoner.isPaused { changeMotion { $0.togglePause() } }
        notice = SessionNotice(text: "Маршрут перебудовано звідси, їдемо далі")
    }

    /// «Додати як зупинку на маршруті».
    public func addStop(_ landmark: Landmark) async {
        guard let destination, let route = engine.route else { return }
        var ahead = remainingStops()
        ahead.append(landmark.place.coordinate)
        ahead.sort { (route.polyline.project($0)?.along ?? 0) < (route.polyline.project($1)?.along ?? 0) }
        await requestRoute(from: position, to: destination, stops: ahead)
    }

    private func remainingStops() -> [Coordinate] {
        guard let route = engine.route else { return stops }
        return stops.filter { (route.polyline.project($0)?.along ?? 0) > engine.along }
    }

    private func requestRoute(from origin: Coordinate?, to place: Place, stops: [Coordinate], startPoint: Place? = nil) async {
        guard let origin else {
            routeError = "Поточна позиція невідома. Дочекайтеся GPS або виберіть маршрут пізніше."
            return
        }
        now = ports.clock.now
        let key = RouteRequestKey(origin: origin, destination: place.coordinate, stops: stops)
        if let cached = routeCache.route(for: key, now: now) {
            ports.log.log("Маршрут узято з кешу, без запиту до MapKit")
            begin(route: cached, destination: place, stops: stops, startPoint: startPoint)
            return
        }
        guard routeThrottle.canRequest(at: now) else {
            routeError = "MapKit тимчасово обмежив запити. Спробуйте через \(Int(routeThrottle.remainingDelay(at: now).rounded(.up))) с."
            return
        }
        isRouting = true
        routeError = nil
        defer { isRouting = false }
        do {
            let route = try await ports.routes.route(from: origin, to: place.coordinate, via: stops)
            routeThrottle.recordSuccess()
            routeCache.store(route, for: key, at: ports.clock.now)
            begin(route: route, destination: place, stops: stops, startPoint: startPoint)
        } catch RouteProviderError.throttled(let retryAfter) {
            let until = routeThrottle.recordThrottled(at: ports.clock.now, retryAfter: retryAfter)
            routeError = "Забагато запитів до MapKit. Повторіть через \(Int(until.timeIntervalSince(ports.clock.now).rounded(.up))) с."
        } catch RouteProviderError.noRoute {
            routeError = "Автомобільний маршрут не знайдено."
        } catch {
            routeError = "Не вдалося побудувати маршрут: \(error.localizedDescription)"
        }
    }

    // MARK: Дії користувача

    public func speedUp() { changeMotion { $0.increaseSpeed() } }
    public func speedDown() { changeMotion { $0.decreaseSpeed() } }
    public func resetSpeed() { changeMotion { $0.resetSpeed() } }
    public func togglePause() { changeMotion { $0.togglePause() } }
    public func ignoreStationary() { changeMotion { $0.ignoreStationary() } }
    public func moveForward() { mutate { engine, now in engine.moveForward(now: now) } }
    public func moveBack() { mutate { engine, now in engine.moveBack(now: now) } }
    public func selectDeadReckoning() { mutate { engine, now in engine.selectDeadReckoning(now: now) } }
    public func selectGPS() { mutate { engine, now in engine.selectGPS(now: now) } }
    public func forceGPS() { mutate { engine, now in engine.forceGPS(now: now) } }
    public func acceptSpoofPrompt() { mutate { engine, now in engine.acceptSpoofPrompt(now: now) } }
    public func keepDeadReckoning() { mutate { engine, now in engine.keepDeadReckoning(now: now) } }
    public func applyTurnSuggestion() { mutate { engine, now in engine.applyTurnSuggestion(now: now) } }
    public func dismissTurnSuggestion() { mutate { engine, _ in engine.dismissTurnSuggestion() } }

    /// Тап по лінії маршруту.
    public func setPosition(along: Double) {
        mutate { engine, now in engine.setPosition(along: along, now: now, reason: .tapOnRoute) }
    }

    /// «Я біля нього»: орієнтир підтверджує, де я зараз.
    public func confirmLandmark(_ landmark: Landmark) {
        mutate { engine, now in engine.setPosition(along: landmark.along, now: now, reason: .landmark) }
    }

    public func clearNotice() {
        notice = nil
    }

    private func mutate(_ body: (inout NavigationEngine, Date) -> Void) {
        now = ports.clock.now
        body(&engine, now)
        processEngineEvents()
    }

    /// Пауза, стоянка чи нова швидкість: спершу довезти точку до цієї миті зі старою швидкістю.
    /// Інакше нова швидкість діяла б і на час до натискання, і точка на екрані відскакувала б назад чи стрибала вперед.
    private func changeMotion(_ body: (inout NavigationEngine) -> Void) {
        mutate { engine, now in
            if isNavigating { engine.tick(now: now) }
            body(&engine)
        }
    }

    /// Рух для екрана: точка між оновленнями рушія їде далі з цією швидкістю (`PositionSmoother`).
    public func motion(at date: Date) -> RouteMotion? {
        guard let route = engine.route else { return nil }
        return RouteMotion(along: engine.displayAlong(at: date), time: alongUpdatedAt, speed: engine.alongSpeed, routeLength: route.polyline.length)
    }

    // MARK: Голос

    private func speakIfNeeded(route: Route) {
        let visible = visibleLandmarks
        let phrases = prompter.update(along: engine.along, route: route, settings: settings) { maneuver in
            LandmarkSelector.nearTurn(visible, maneuver: maneuver)
        }
        guard settings[.voiceEnabled] else { return }
        for phrase in phrases {
            ports.speech.speak(phrase)
            lastSpokenPhrase = phrase
        }
    }

    // MARK: Орієнтири

    /// «Оновити»: заново запитати орієнтири поруч (вікно позаду, 2 км попереду, найближчий поворот),
    /// не чекаючи автоматики. Знайдені раніше місця лишаються. Після помилки мережі повтор одразу,
    /// а обмеження від самого MapKit треба перечекати: інакше MapKit обмежить ще довше.
    public func refreshLandmarks() {
        now = ports.clock.now
        guard isNavigating, let route = engine.route else { return }
        let near = (engine.along - LandmarkPlanner.windowLength)..<(engine.along + LandmarkPlanner.nearHorizon)
        let nextTurn = LandmarkPlanner.turns(of: route).first { $0.along + LandmarkPlanner.turnExit > engine.along }
        for area in landmarkLoaded.keys {
            let range = LandmarkPlanner.range(of: area, route: route)
            if range.lowerBound < near.upperBound && range.upperBound > near.lowerBound || area == nextTurn.map({ .turn($0.id) }) {
                landmarkLoaded[area] = nil
            }
        }
        if !placeThrottle.canRequest(at: now) {
            if isThrottledByMapKit {
                let wait = Int(placeThrottle.remainingDelay(at: now).rounded(.up))
                ports.log.log("Орієнтири: оновлення вручну, але MapKit обмежив запити, повтор через \(wait) с")
                notice = SessionNotice(text: "MapKit тимчасово обмежив запити. Оновлю через \(wait) с")
            } else {
                placeThrottle.recordSuccess()
                landmarkStatus.retryAt = nil
            }
        }
        ports.log.log("Орієнтири: оновлення вручну біля \(Int(engine.along)) м")
        loadLandmarksIfNeeded()
    }

    private func resetLandmarkLoading() {
        landmarkLoaded.removeAll()
        denseWindows.removeAll()
        landmarkStatus = LandmarkLoadStatus()
        // Відповіді на запити, що ще в дорозі, стосуються старого маршруту: позначки «завантажено» з них не беремо.
        landmarkGeneration += 1
        landmarkTask = nil
    }

    private func nextLandmarkRequest(generation: Int) -> LandmarkRequest? {
        guard generation == landmarkGeneration, isNavigating, let route = engine.route,
              placeThrottle.canRequest(at: ports.clock.now) else { return nil }
        return LandmarkPlanner.next(
            along: engine.along,
            route: route,
            segmentLength: settings.landmarkSegmentLength,
            categories: settings.enabledCategories,
            loaded: landmarkLoaded,
            denseWindows: denseWindows
        )
    }

    /// Запити по одному за раз, щоб не впертися в обмеження MapKit. Після кожної відповіді наступну ділянку
    /// вибираємо заново: позиція могла зрушити, і найважливіше тепер інше.
    private func loadLandmarksIfNeeded() {
        let generation = landmarkGeneration
        guard landmarkTask == nil, nextLandmarkRequest(generation: generation) != nil else { return }
        let places = ports.places
        let id = UUID()
        let task = Task { [weak self] in
            while let self, let request = self.nextLandmarkRequest(generation: generation), let route = self.engine.route {
                self.landmarkStatus.loading = request.area
                let region = route.polyline.region(for: request.range, padding: self.settings[.landmarkCorridor])
                do {
                    let found = try await places.pointsOfInterest(in: region, categories: request.categories)
                    self.landmarksArrived(found, for: request, generation: generation)
                } catch PlaceSearchError.notFound {
                    // MapKit так відповідає, коли в регіоні немає місць потрібних типів: ділянка завантажена, просто порожня.
                    self.landmarksArrived([], for: request, generation: generation)
                } catch {
                    self.landmarkRequestFailed(error, generation: generation)
                    break
                }
            }
            guard let self else { return }
            self.pendingTasks[id] = nil
            if generation == self.landmarkGeneration {
                self.landmarkTask = nil
                self.landmarkStatus.loading = nil
            }
        }
        landmarkTask = task
        pendingTasks[id] = task
    }

    private func landmarksArrived(_ found: [PlaceCandidate], for request: LandmarkRequest, generation: Int) {
        // Місця запам'ятовуємо, навіть якщо маршрут тим часом змінився.
        merge(found)
        guard generation == landmarkGeneration else { return }
        now = ports.clock.now
        placeThrottle.recordSuccess()
        isThrottledByMapKit = false
        landmarkLoaded[request.area, default: []].formUnion(request.categories)
        if case .window(let window) = request.area, found.count >= LandmarkPlanner.denseThreshold {
            denseWindows.insert(window)
        }
        landmarkStatus.requests += 1
        landmarkStatus.lastFound = found.count
        landmarkStatus.lastSuccessAt = now
        landmarkStatus.lastError = nil
        landmarkStatus.retryAt = nil
        if let route = engine.route { updateLandmarkCoverage(route: route) }
        ports.log.log("Орієнтири: \(Self.describe(request.area)) \(Int(request.range.lowerBound))–\(Int(request.range.upperBound)) м, типів \(request.categories.count), знайдено \(found.count)")
    }

    private func landmarkRequestFailed(_ error: any Error, generation: Int) {
        now = ports.clock.now
        let until: Date
        let message: String
        // Обмеження діє на весь застосунок, тож записуємо його, навіть якщо маршрут уже інший.
        if case PlaceSearchError.throttled(let retryAfter) = error {
            until = placeThrottle.recordThrottled(at: now, retryAfter: retryAfter)
            isThrottledByMapKit = true
            message = "MapKit тимчасово обмежив запити"
        } else {
            // Мережа недоступна: спробуємо пізніше з тим самим backoff, щоб не засипати запитами.
            until = placeThrottle.recordThrottled(at: now)
            isThrottledByMapKit = false
            if case PlaceSearchError.failed(let text) = error {
                message = "Немає відповіді: \(text)"
            } else {
                message = "Немає відповіді: \(error.localizedDescription)"
            }
        }
        ports.log.log("Орієнтири: запит не вдався (\(message)), повтор через \(Int(until.timeIntervalSince(now).rounded(.up))) с")
        guard generation == landmarkGeneration else { return }
        landmarkStatus.failures += 1
        landmarkStatus.lastError = message
        landmarkStatus.retryAt = until
    }

    private func updateLandmarkCoverage(route: Route) {
        let coverage = LandmarkPlanner.coverageAhead(along: engine.along, route: route, categories: settings.enabledCategories, loaded: landmarkLoaded)
        if landmarkStatus.coverageAhead != coverage { landmarkStatus.coverageAhead = coverage }
    }

    static func describe(_ area: LandmarkArea) -> String {
        switch area {
        case .window(let window): "вікно \(window)"
        case let .half(window, part): "половина \(part + 1) вікна \(window)"
        case .turn(let id): "поворот #\(id)"
        }
    }

    private func merge(_ found: [PlaceCandidate]) {
        var known = Set(landmarkCandidates.map(\.id))
        let fresh = found.filter { known.insert($0.id).inserted }
        guard !fresh.isEmpty else { return }
        landmarkCandidates += fresh
        if landmarkCandidates.count > Self.maxCandidates {
            landmarkCandidates.removeFirst(landmarkCandidates.count - Self.maxCandidates)
            reselectLandmarks()
        } else if let route = engine.route {
            // Відбираємо лише нові місця: повний перебір тисяч місць на кожну відповідь не потрібен.
            let added = LandmarkSelector.select(fresh, polyline: route.polyline, corridor: settings[.landmarkCorridor])
            if !added.isEmpty { landmarks = (landmarks + added).sorted { $0.along < $1.along } }
        }
    }

    private func reselectLandmarks() {
        guard let route = engine.route else {
            landmarks = []
            return
        }
        landmarks = LandmarkSelector.select(landmarkCandidates, polyline: route.polyline, corridor: settings[.landmarkCorridor])
    }

    /// Дочекатися фонових запитів (для тестів).
    public func settle() async {
        while let (id, task) = pendingTasks.first {
            await task.value
            pendingTasks[id] = nil
        }
    }

    // MARK: Журнал режимів

    private func processEngineEvents() {
        if engine.along != lastAlong {
            lastAlong = engine.along
            alongUpdatedAt = now
        }
        for event in engine.drainEvents() {
            switch event {
            case let .modeChanged(from, to, reason):
                ports.log.log("Режим: \(from.title) → \(to.title) [\(from.rawValue)->\(to.rawValue)], причина: \(reason.title) [\(reason.rawValue)], позиція \(Int(engine.along)) м з \(Int(engine.routeLength)) м")
                lastProgressLog = now
                if to == .gps, reason == .userAcceptedGPS || reason == .userSelectedGPS {
                    notice = SessionNotice(text: "Перейшли на GPS")
                } else if to == .gps, reason == .userForcedGPS {
                    notice = SessionNotice(text: "Ведемо за GPS. Сам на розрахункову не перейде, доки не перемкнете")
                }
            case let .spoofSuspected(kind, distance):
                ports.log.log("Підозра на підміну GPS: \(kind.title) [\(kind.rawValue)], зсув \(Int(distance)) м")
            case let .returnPrompt(distance):
                ports.log.log("GPS показує інше місце: \(Int(distance)) м від розрахункової позиції, питаю користувача")
            case .promptDismissed:
                ports.log.log("Користувач лишив розрахункову позицію")
                notice = SessionNotice(text: "Лишаємось на розрахунковій позиції")
            case .gpsUnavailable:
                ports.log.log("Ручний перемикач на GPS: GPS зараз непридатний, повернемося автоматично")
                notice = SessionNotice(text: "GPS ще непридатний. Повернемося автоматично, щойно сигнал стане точним")
            case let .positionCorrected(from, to, reason):
                ports.log.log("Корекція позиції (\(reason.title)): \(Int(from)) → \(Int(to)) м")
                notice = SessionNotice(text: correctionText(reason: reason, delta: to - from))
            case let .offRoute(distance):
                ports.log.log("GPS відхилився від маршруту на \(Int(distance)) м")
            case let .turnSuggested(maneuverID, distance):
                ports.log.log("Гіроскоп: поворот, а розрахункова точка ще за \(Int(distance)) м до маневру #\(maneuverID)")
            case let .activityChanged(activity):
                ports.log.log("Датчики руху: \(activity.title)")
            case .stationaryIgnored:
                ports.log.log("Датчики бачать стоянку, але водій рушив: точка їде, доки датчики не побачать рух")
            case .arrived:
                // Фразу прибуття озвучує VoicePrompter, тут лише журнал.
                ports.log.log("Прибуття до пункту призначення")
            }
        }
    }

    private func correctionText(reason: CorrectionReason, delta: Double) -> String {
        switch reason {
        case .nudgeForward, .nudgeBack:
            "Позицію зсунуто на \(delta >= 0 ? "+" : "−")\(Int(abs(delta).rounded())) м"
        case .tapOnRoute, .mapPoint:
            "Позицію переставлено"
        case .landmark:
            "Позицію підтверджено орієнтиром"
        case .turnSnap:
            "Позицію підтягнуто до повороту"
        }
    }

    private func logProgressIfNeeded() {
        guard engine.mode == .deadReckoning else { return }
        if let last = lastProgressLog, now.timeIntervalSince(last) < Self.progressLogInterval { return }
        lastProgressLog = now
        let info = engine.speedInfo
        let moving = engine.reckoner.isPaused ? "пауза" : engine.reckoner.isStationary ? "стоянка" : "рух"
        ports.log.log("Розрахункова позиція (\(moving)): \(Int(engine.along)) м з \(Int(engine.routeLength)) м, \(UkrainianFormat.speed(info.speed)) [\(info.source.rawValue)], без GPS \(Int(engine.timeWithoutGPS(at: now) ?? 0)) с")
    }

    // MARK: Збереження

    public func persist() {
        lastPersisted = now
        ports.store.save(snapshot())
    }

    public func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            route: engine.route,
            destination: destination,
            stops: stops,
            along: engine.along,
            isNavigating: isNavigating,
            reckoner: engine.reckoner,
            landmarkCandidates: landmarkCandidates,
            routeCache: routeCache,
            savedAt: now
        )
    }

    private func restore(from snapshot: SessionSnapshot) {
        routeCache = snapshot.routeCache
        guard snapshot.isNavigating, let route = snapshot.route else { return }
        engine.restore(route: route, along: snapshot.along, reckoner: snapshot.reckoner, now: now)
        destination = snapshot.destination
        stops = snapshot.stops
        isNavigating = true
        landmarkCandidates = snapshot.landmarkCandidates
        reselectLandmarks()
        ports.log.log("Відновлено навігацію після перезапуску: \(Int(snapshot.along)) м з \(Int(route.polyline.length)) м")
    }
}
