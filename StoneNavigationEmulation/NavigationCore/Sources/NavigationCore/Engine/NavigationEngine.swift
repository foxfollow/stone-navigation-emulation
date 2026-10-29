import Foundation

public enum NavigationMode: String, Codable, Sendable {
    case gps
    case deadReckoning

    public var title: String {
        switch self {
        case .gps: "GPS"
        case .deadReckoning: "Розрахункова позиція"
        }
    }
}

/// Хто керує режимом: автоматика чи ручний перемикач.
public enum ModeControl: String, Codable, Sendable {
    case automatic
    case manualDeadReckoning
    /// Водій сам вибрав GPS: позиція йде за кожною точкою, без автоматичного переходу на розрахункову.
    case manualGPS
}

/// Чи придатний зараз GPS для автоматичного переходу на нього.
public enum GPSAvailability: Sendable, Equatable {
    case usable
    /// Точність гірша за поріг; nil, якщо точність невідома.
    case poorAccuracy(Double?)
    /// Остання точка старша за поріг застарілості.
    case stale(age: TimeInterval)
    case noSignal
}

public enum ModeReason: String, Codable, Sendable {
    case start
    case gpsRestored
    case userAcceptedGPS
    case userSelectedGPS
    case userForcedGPS
    case userSelectedDeadReckoning
    case userMovedPosition
    case chosenStart
    case locationError
    case staleFix
    case poorAccuracy
    case noFix
    case spoofJump
    case spoofSpeed
    case spoofCourse

    public var title: String {
        switch self {
        case .start: "старт"
        case .gpsRestored: "GPS знову точний"
        case .userAcceptedGPS: "користувач перейшов на GPS"
        case .userSelectedGPS: "ручний перемикач: GPS"
        case .userForcedGPS: "GPS увімкнено вручну"
        case .userSelectedDeadReckoning: "ручний перемикач: розрахункова"
        case .userMovedPosition: "ручна корекція позиції"
        case .chosenStart: "старт із вибраної точки"
        case .locationError: "помилка геолокації"
        case .staleFix: "застаріла точка"
        case .poorAccuracy: "погана точність"
        case .noFix: "немає точок GPS"
        case .spoofJump: "підміна: стрибок позиції"
        case .spoofSpeed: "підміна: неможлива швидкість"
        case .spoofCourse: "підміна: курс без повороту"
        }
    }
}

public enum CorrectionReason: String, Codable, Sendable {
    case nudgeForward
    case nudgeBack
    case tapOnRoute
    case landmark
    case turnSnap
    /// «Я тут» з довгого тапу по карті.
    case mapPoint

    public var title: String {
        switch self {
        case .nudgeForward: "вперед"
        case .nudgeBack: "назад"
        case .tapOnRoute: "тап по маршруту"
        case .landmark: "підтверджено орієнтиром"
        case .turnSnap: "підтягнуто до повороту"
        case .mapPoint: "точка на карті"
        }
    }
}

/// Запит «GPS показує інше місце. Перейти на GPS?».
public struct SpoofPrompt: Sendable, Equatable {
    public var fix: LocationFix
    /// Відстань від GPS-точки до розрахункової позиції, метри.
    public var distance: Double
    public var shownAt: Date
}

public struct OffRouteState: Sendable, Equatable {
    public var distance: Double
    public var gpsCoordinate: Coordinate
}

public struct TurnSuggestion: Sendable, Equatable {
    public var maneuver: Maneuver
    /// Скільки лишалося до повороту в момент виявлення, метри.
    public var distance: Double
    public var detectedAt: Date
}

public enum EngineEvent: Sendable, Equatable {
    case modeChanged(from: NavigationMode, to: NavigationMode, reason: ModeReason)
    case spoofSuspected(SpoofKind, distance: Double)
    case returnPrompt(distance: Double)
    case promptDismissed
    case gpsUnavailable
    case positionCorrected(from: Double, to: Double, reason: CorrectionReason)
    case offRoute(distance: Double)
    case turnSuggested(maneuverID: Int, distance: Double)
    case activityChanged(MotionActivity)
    /// Водій сказав «Рушити», хоч датчики бачать стоянку.
    case stationaryIgnored
    case arrived
}

/// Машина станів режимів і позиція на маршруті. Чиста структура: час передається явно.
public struct NavigationEngine: Sendable {
    public private(set) var settings: NavigationSettings
    public private(set) var route: Route?
    public private(set) var mode: NavigationMode = .gps
    public private(set) var control: ModeControl = .automatic
    public private(set) var modeReason: ModeReason = .start
    public private(set) var modeSince: Date
    /// Оцінка позиції: дистанція від початку маршруту, метри.
    public private(set) var along: Double = 0
    public private(set) var reckoner = DeadReckoner()
    /// Остання точка, прийнята як добра.
    public private(set) var lastGoodFix: LocationFix?
    /// Остання отримана точка будь-якої якості.
    public private(set) var lastRawFix: LocationFix?
    public private(set) var lastFixReceivedAt: Date?
    public private(set) var gpsLostSince: Date?
    public private(set) var spoofPrompt: SpoofPrompt?
    public private(set) var offRoute: OffRouteState?
    public private(set) var turnSuggestion: TurnSuggestion?
    public private(set) var hasArrived = false
    /// Стоянку за датчиками знято вручну: наступну стоянку враховуємо, лише коли датчики знову побачать рух.
    public private(set) var isStationaryIgnored = false

    private var lastGoodFixReceivedAt: Date?
    private var goodStreakStart: Date?
    private var previousStreakFix: LocationFix?
    private var promptSuppressedUntil: Date?
    private var lastTick: Date?
    private var trackingStartedAt: Date
    private var transition: Transition?
    private var events: [EngineEvent] = []

    /// Вікно пошуку проєкції GPS навколо поточної позиції, щоб не «перескочити» на сусідню ділянку маршруту.
    static let projectionWindowBack = 300.0
    static let projectionWindowAhead = 3000.0

    private struct Transition: Sendable {
        var offset: Double
        var start: Date
        var duration: TimeInterval
    }

    public init(settings: NavigationSettings = .standard, now: Date) {
        self.settings = settings
        self.modeSince = now
        self.trackingStartedAt = now
    }

    // MARK: Налаштування і маршрут

    public mutating func apply(settings: NavigationSettings) {
        self.settings = settings
    }

    public mutating func setRoute(_ route: Route?, along: Double = 0, now: Date) {
        self.route = route
        self.along = route?.polyline.clamp(along) ?? 0
        hasArrived = false
        offRoute = nil
        spoofPrompt = nil
        turnSuggestion = nil
        transition = nil
        trackingStartedAt = now
        lastTick = now
    }

    /// Маршрут починається з точки, яку вибрав водій, а не з GPS. Якщо свіжий GPS поруч зі стартом,
    /// лишаємось на GPS. Інакше розрахункова позиція стоїть на старті на паузі, доки водій не натисне «Далі»:
    /// авто ще не рушило, а GPS або зник, або показує інше місце.
    public mutating func startAtChosenPoint(now: Date) {
        // Водій сам вибрав GPS: лишаємось на ньому.
        guard let route, control != .manualGPS else { return }
        let start = route.polyline.coordinate(at: 0)
        if mode == .gps, control == .automatic,
           let fix = lastGoodFix, let received = lastGoodFixReceivedAt,
           now.timeIntervalSince(received) <= settings[.staleAge],
           Geo.distance(fix.coordinate, start) <= settings[.spoofDistance] {
            return
        }
        if mode == .gps {
            enterDeadReckoning(.chosenStart, now: now)
            // GPS не зник, а показує інше місце: таймер «без GPS» рахуємо від старту.
            gpsLostSince = now
        }
        along = 0
        transition = nil
        reckoner.isPaused = true
        lastTick = now
    }

    /// Відновлення після перезапуску: маршрут, позиція і ручна швидкість.
    public mutating func restore(route: Route, along: Double, reckoner: DeadReckoner, now: Date) {
        setRoute(route, along: along, now: now)
        self.reckoner = reckoner
        self.reckoner.isStationary = false
    }

    public mutating func drainEvents() -> [EngineEvent] {
        defer { events.removeAll() }
        return events
    }

    // MARK: Вихідні дані

    public var routeLength: Double { route?.polyline.length ?? 0 }
    public var remainingDistance: Double { max(0, routeLength - along) }
    public var rawGPSCoordinate: Coordinate? { lastRawFix?.coordinate }

    /// Позиція для відображення з урахуванням плавного переходу.
    public func displayAlong(at now: Date) -> Double {
        guard let transition, let route else { return along }
        let progress = min(1, max(0, now.timeIntervalSince(transition.start) / transition.duration))
        let eased = progress * progress * (3 - 2 * progress)
        return route.polyline.clamp(along + transition.offset * (1 - eased))
    }

    /// Моя позиція: завжди на лінії маршруту; без маршруту остання точка GPS.
    public func position(at now: Date) -> Coordinate? {
        guard let route else { return lastRawFix?.coordinate }
        return route.polyline.coordinate(at: displayAlong(at: now))
    }

    public func heading(at now: Date) -> Double? {
        guard let route else { return lastRawFix.flatMap { $0.hasCourse ? $0.course : nil } }
        return route.polyline.bearing(at: displayAlong(at: now))
    }

    /// Швидкість розрахункової позиції та її джерело.
    public var speedInfo: (speed: Double, source: SpeedSource) {
        reckoner.speed(routeAverage: route?.averageSpeed, settings: settings)
    }

    public func gpsAvailability(at now: Date) -> GPSAvailability {
        guard let fix = lastRawFix else { return .noSignal }
        let age = now.timeIntervalSince(fix.timestamp)
        if age > settings[.staleAge] { return .stale(age: age) }
        guard fix.hasValidAccuracy else { return .poorAccuracy(nil) }
        guard fix.horizontalAccuracy <= settings[.enterAccuracy] else { return .poorAccuracy(fix.horizontalAccuracy) }
        return .usable
    }

    /// Швидкість точки вздовж маршруту зараз, м/с: у розрахунковому режимі з рушія (0 на паузі й стоянці),
    /// на GPS з останньої точки GPS. Екрану вона потрібна, щоб точка між оновленнями їхала плавно.
    public var alongSpeed: Double {
        guard let route, !hasArrived, along < route.polyline.length else { return 0 }
        switch mode {
        case .deadReckoning: return reckoner.movingSpeed(routeAverage: route.averageSpeed, settings: settings)
        case .gps: return currentGPSSpeed ?? 0
        }
    }

    public var currentGPSSpeed: Double? {
        guard let speed = lastGoodFix?.speed, speed >= 0 else { return nil }
        return speed
    }

    /// Час до прибуття, секунди.
    public var remainingTime: TimeInterval? {
        guard let route else { return nil }
        let fallback = route.averageSpeed ?? settings.defaultSpeed
        let speed: Double
        switch mode {
        case .deadReckoning:
            let manual = speedInfo.speed
            speed = manual > 0.5 ? manual : fallback
        case .gps:
            speed = route.averageSpeed ?? reckoner.lastGPSSpeed ?? settings.defaultSpeed
        }
        return remainingDistance / max(speed, 0.5)
    }

    public func timeWithoutGPS(at now: Date) -> TimeInterval? {
        guard mode == .deadReckoning else { return nil }
        return max(0, now.timeIntervalSince(gpsLostSince ?? modeSince))
    }

    public var nextManeuver: (maneuver: Maneuver, distance: Double)? {
        guard let route, let maneuver = route.nextManeuver(after: along) else { return nil }
        return (maneuver, maneuver.along - along)
    }

    // MARK: Події геолокації

    public mutating func handle(_ event: LocationEvent, now: Date) {
        switch event {
        case .error:
            resetStreak()
            if mode == .gps, control == .automatic {
                enterDeadReckoning(.locationError, now: now)
            }
        case .fix(let fix):
            handle(fix: fix, now: now)
        }
    }

    private mutating func handle(fix: LocationFix, now: Date) {
        lastFixReceivedAt = now
        lastRawFix = fix
        let isStale = now.timeIntervalSince(fix.timestamp) > settings[.staleAge]

        switch mode {
        case .gps where control == .manualGPS:
            // Водій сам вибрав GPS: беремо кожну точку, без перевірок точності, віку і підміни.
            if let last = lastGoodFix, fix.timestamp < last.timestamp { return }
            accept(fix, now: now)
        case .gps:
            if isStale {
                enterDeadReckoning(.staleFix, now: now)
                return
            }
            guard fix.hasValidAccuracy, fix.horizontalAccuracy <= settings[.enterAccuracy] else {
                enterDeadReckoning(.poorAccuracy, now: now)
                return
            }
            if let previous = lastGoodFix,
               let kind = SpoofDetector.check(previous: previous, current: fix, settings: settings, route: route) {
                events.append(.spoofSuspected(kind, distance: Geo.distance(previous.coordinate, fix.coordinate)))
                enterDeadReckoning(kind.modeReason, now: now)
                return
            }
            accept(fix, now: now)
        case .deadReckoning:
            considerReturn(to: fix, isStale: isStale, now: now)
        }
    }

    private mutating func accept(_ fix: LocationFix, now: Date) {
        lastGoodFix = fix
        lastGoodFixReceivedAt = now
        gpsLostSince = nil
        if fix.speed >= DeadReckoner.minimumUsefulGPSSpeed {
            reckoner.lastGPSSpeed = fix.speed
        }
        guard let route, let projection = project(fix.coordinate, on: route) else { return }
        along = projection.along
        if projection.offset > settings[.offRouteThreshold] {
            if offRoute == nil { events.append(.offRoute(distance: projection.offset)) }
            offRoute = OffRouteState(distance: projection.offset, gpsCoordinate: fix.coordinate)
        } else {
            offRoute = nil
        }
        checkArrival()
    }

    /// Проєкція GPS на маршрут: спершу поруч із поточною позицією, якщо там далеко, по всьому маршруту.
    private func project(_ coordinate: Coordinate, on route: Route) -> RouteProjection? {
        let window = (along - Self.projectionWindowBack)...(along + Self.projectionWindowAhead)
        if let local = route.polyline.project(coordinate, in: window), local.offset <= settings[.offRouteThreshold] * 2 {
            return local
        }
        return route.polyline.project(coordinate)
    }

    private mutating func considerReturn(to fix: LocationFix, isStale: Bool, now: Date) {
        guard control == .automatic,
              !isStale,
              fix.hasValidAccuracy,
              fix.horizontalAccuracy <= settings[.returnAccuracy] else {
            resetStreak()
            return
        }
        if let previous = previousStreakFix,
           SpoofDetector.check(previous: previous, current: fix, settings: settings, route: route) != nil {
            goodStreakStart = nil
        }
        previousStreakFix = fix
        let streakStart = goodStreakStart ?? fix.timestamp
        goodStreakStart = streakStart
        guard fix.timestamp.timeIntervalSince(streakStart) >= settings[.returnDuration] else { return }

        guard let route else {
            switchToGPS(with: fix, reason: .gpsRestored, now: now)
            return
        }
        let distance = Geo.distance(route.polyline.coordinate(at: along), fix.coordinate)
        if distance <= settings[.spoofDistance] {
            switchToGPS(with: fix, reason: .gpsRestored, now: now)
            return
        }
        if let until = promptSuppressedUntil, now < until { return }
        let isNew = spoofPrompt == nil
        spoofPrompt = SpoofPrompt(fix: fix, distance: distance, shownAt: spoofPrompt?.shownAt ?? now)
        if isNew { events.append(.returnPrompt(distance: distance)) }
    }

    private mutating func resetStreak() {
        goodStreakStart = nil
        previousStreakFix = nil
    }

    // MARK: Перемикання режимів

    private mutating func enterDeadReckoning(_ reason: ModeReason, now: Date) {
        guard mode != .deadReckoning else { return }
        if let route, let lastGood = lastGoodFixReceivedAt {
            // Точка рухалась і після останньої доброї точки: доганяємо пропущений час.
            let elapsed = min(max(0, now.timeIntervalSince(lastGood)), settings[.staleAge] + settings[.updateInterval])
            along = route.polyline.clamp(along + reckoner.movingSpeed(routeAverage: route.averageSpeed, settings: settings) * elapsed)
        }
        let previous = mode
        mode = .deadReckoning
        modeReason = reason
        modeSince = now
        gpsLostSince = lastGoodFixReceivedAt ?? now
        offRoute = nil
        lastTick = now
        resetStreak()
        events.append(.modeChanged(from: previous, to: .deadReckoning, reason: reason))
    }

    private mutating func switchToGPS(with fix: LocationFix, reason: ModeReason, now: Date) {
        let previous = mode
        let previousAlong = along
        mode = .gps
        modeReason = reason
        modeSince = now
        spoofPrompt = nil
        promptSuppressedUntil = nil
        turnSuggestion = nil
        // Пауза стосується лише розрахункової точки: після GPS вона не має «застигнути» при наступній втраті сигналу.
        reckoner.isPaused = false
        resetStreak()
        accept(fix, now: now)
        startTransition(from: previousAlong, now: now)
        if previous != .gps {
            events.append(.modeChanged(from: previous, to: .gps, reason: reason))
        }
    }

    private mutating func startTransition(from previousAlong: Double, now: Date) {
        let duration = settings[.transitionDuration]
        guard duration > 0, abs(previousAlong - along) > 1 else {
            transition = nil
            return
        }
        transition = Transition(offset: previousAlong - along, start: now, duration: duration)
    }

    // MARK: Таймер

    public mutating func tick(now: Date) {
        let previousTick = lastTick ?? now
        lastTick = now
        guard let route else { return }

        if mode == .gps, control == .automatic {
            let reference = lastFixReceivedAt ?? trackingStartedAt
            if now.timeIntervalSince(reference) > settings[.staleAge] {
                enterDeadReckoning(lastFixReceivedAt == nil ? .noFix : .staleFix, now: now)
                return
            }
        }

        if mode == .deadReckoning {
            // Без обмеження зверху: якщо iOS призупинила застосунок, авто все одно їхало.
            let elapsed = max(0, now.timeIntervalSince(previousTick))
            let speed = reckoner.movingSpeed(routeAverage: route.averageSpeed, settings: settings)
            along = route.polyline.clamp(along + speed * elapsed)
            if let received = lastFixReceivedAt, now.timeIntervalSince(received) > settings[.staleAge] {
                resetStreak()
            }
        }

        if let suggestion = turnSuggestion, along >= suggestion.maneuver.along - 1 {
            turnSuggestion = nil
        }
        if let transition, now.timeIntervalSince(transition.start) >= transition.duration {
            self.transition = nil
        }
        checkArrival()
    }

    private mutating func checkArrival() {
        guard route != nil, !hasArrived, remainingDistance <= settings[.voiceAtTurnDistance] else { return }
        hasArrived = true
        events.append(.arrived)
    }

    // MARK: Дії користувача

    /// Ручний перемикач: розрахункова позиція без автоматичного повернення.
    public mutating func selectDeadReckoning(now: Date) {
        control = .manualDeadReckoning
        spoofPrompt = nil
        if mode == .deadReckoning {
            modeReason = .userSelectedDeadReckoning
        } else {
            enterDeadReckoning(.userSelectedDeadReckoning, now: now)
        }
    }

    /// Ручний перемикач: повернутись на GPS, якщо зараз є придатна точка.
    public mutating func selectGPS(now: Date) {
        control = .automatic
        spoofPrompt = nil
        promptSuppressedUntil = nil
        guard mode == .deadReckoning else { return }
        if gpsAvailability(at: now) == .usable, let fix = lastRawFix {
            switchToGPS(with: fix, reason: .userSelectedGPS, now: now)
        } else {
            events.append(.gpsUnavailable)
        }
    }

    /// «Все одно вести за GPS»: водій довіряє GPS, навіть неточному чи старому. Позиція йде за кожною
    /// точкою, автоматичного переходу на розрахункову немає, доки водій сам не перемкне режим.
    public mutating func forceGPS(now: Date) {
        let previous = mode
        let previousAlong = along
        control = .manualGPS
        mode = .gps
        modeReason = .userForcedGPS
        modeSince = now
        spoofPrompt = nil
        promptSuppressedUntil = nil
        turnSuggestion = nil
        reckoner.isPaused = false
        resetStreak()
        if let fix = lastRawFix {
            accept(fix, now: now)
            startTransition(from: previousAlong, now: now)
        }
        if previous != .gps {
            events.append(.modeChanged(from: previous, to: .gps, reason: .userForcedGPS))
        }
    }

    /// «Перейти на GPS» у запиті про підміну.
    public mutating func acceptSpoofPrompt(now: Date) {
        guard let prompt = spoofPrompt else { return }
        control = .automatic
        var fix = prompt.fix
        if let latest = lastRawFix, latest.timestamp > fix.timestamp,
           latest.hasValidAccuracy, latest.horizontalAccuracy <= settings[.returnAccuracy] {
            fix = latest
        }
        switchToGPS(with: fix, reason: .userAcceptedGPS, now: now)
    }

    /// «Лишити розрахункову»: запит не повторюється протягом `promptCooldown`.
    public mutating func keepDeadReckoning(now: Date) {
        guard spoofPrompt != nil else { return }
        spoofPrompt = nil
        promptSuppressedUntil = now.addingTimeInterval(settings[.promptCooldown])
        resetStreak()
        events.append(.promptDismissed)
    }

    /// Переставити позицію на маршруті. У режимі GPS це означає, що GPS бреше: вмикаємо ручну розрахункову.
    public mutating func setPosition(along target: Double, now: Date, reason: CorrectionReason) {
        guard let route else { return }
        if mode == .gps {
            control = .manualDeadReckoning
            enterDeadReckoning(.userMovedPosition, now: now)
        }
        let previous = along
        along = route.polyline.clamp(target)
        transition = nil
        if along < previous { hasArrived = false }
        if let suggestion = turnSuggestion, along >= suggestion.maneuver.along - 1 { turnSuggestion = nil }
        lastTick = now
        events.append(.positionCorrected(from: previous, to: along, reason: reason))
    }

    public mutating func moveForward(now: Date) {
        setPosition(along: along + settings[.shiftStepMeters], now: now, reason: .nudgeForward)
    }

    public mutating func moveBack(now: Date) {
        setPosition(along: along - settings[.shiftStepMeters], now: now, reason: .nudgeBack)
    }

    public mutating func increaseSpeed() {
        reckoner.increase(routeAverage: route?.averageSpeed, settings: settings)
    }

    public mutating func decreaseSpeed() {
        reckoner.decrease(routeAverage: route?.averageSpeed, settings: settings)
    }

    public mutating func resetSpeed() {
        reckoner.resetManualSpeed()
    }

    /// «Пауза» / «Далі». «Далі» означає, що авто рушило: стоянку за датчиками теж знімаємо.
    public mutating func togglePause() {
        if reckoner.isPaused {
            reckoner.isPaused = false
            ignoreStationary()
        } else {
            reckoner.isPaused = true
        }
    }

    /// «Рушити»: точка їде, хоч датчики бачать стоянку (телефон лежить, а перевірити треба в русі,
    /// або датчик помилився). Діє, доки датчики не побачать рух; наступна справжня стоянка знову зупинить точку.
    public mutating func ignoreStationary() {
        guard reckoner.isStationary else { return }
        reckoner.isStationary = false
        isStationaryIgnored = true
        events.append(.stationaryIgnored)
    }

    // MARK: Датчики

    public mutating func handleActivity(_ activity: MotionActivity) {
        guard activity != .unknown else { return }
        let stationary = activity == .stationary
        if isStationaryIgnored {
            guard !stationary else { return }
            isStationaryIgnored = false
        }
        guard reckoner.isStationary != stationary else { return }
        reckoner.isStationary = stationary
        events.append(.activityChanged(activity))
    }

    /// Гіроскоп зафіксував поворот (`degrees` > 0 ліворуч). Якщо розрахункова точка ще не доїхала
    /// до відповідного повороту маршруту, пропонуємо підтягнути її туди.
    public mutating func handleTurn(degrees: Double, now: Date) {
        guard mode == .deadReckoning, let route else { return }
        let limit = along + settings[.turnSnapMaxDistance]
        let turnsLeft = degrees > 0
        guard let maneuver = route.maneuvers.first(where: { candidate in
            guard candidate.isTurn, candidate.along > along + 1, candidate.along <= limit,
                  let angle = candidate.turnAngle else { return false }
            return (angle < 0) == turnsLeft
        }) else { return }
        let distance = maneuver.along - along
        turnSuggestion = TurnSuggestion(maneuver: maneuver, distance: distance, detectedAt: now)
        events.append(.turnSuggested(maneuverID: maneuver.id, distance: distance))
    }

    public mutating func applyTurnSuggestion(now: Date) {
        guard let suggestion = turnSuggestion else { return }
        turnSuggestion = nil
        setPosition(along: suggestion.maneuver.along, now: now, reason: .turnSnap)
    }

    public mutating func dismissTurnSuggestion() {
        turnSuggestion = nil
    }
}
