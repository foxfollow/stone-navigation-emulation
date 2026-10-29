import MapKit
import NavigationCore
import Observation
import SwiftUI
import UIKit

/// Стан екрана: камера, відкриті картки, затемнення, головний цикл оновлення і idle timer.
@MainActor
@Observable
final class AppModel {
    var camera: MapCameraPosition = .automatic
    /// Камера стежить за моєю позицією: щипок лише змінює висоту, перетягування стеження вимикає.
    var isFollowing = true
    var cameraHeading: Double = 0
    /// Висота камери в режимі стеження: її змінює щипок, і вона лишається після «Центрувати». Запам'ятовується між запусками.
    var followDistance: CLLocationDistance {
        didSet { uiStorage.set(followDistance, forKey: Self.followDistanceKey) }
    }
    /// Висота камери зараз, хай хто її змінив: з нею стежить «Центрувати».
    private(set) var cameraDistance: CLLocationDistance?
    /// Позиція і курс на екрані: між оновленнями рушія точка їде плавно, на кожному кадрі.
    private(set) var displayAlong: Double?
    private(set) var displayHeading: Double?
    var selectedLandmark: Landmark?
    var showLandmarkList = false
    var showSettings = false
    var showSearch = false
    /// Вибір режиму позиції (тап по індикатору або «Перейти на GPS», коли GPS непридатний).
    var showModeOptions = false
    var pendingDestination: Place?
    /// Звідки прокласти наступний маршрут; nil це моя позиція.
    var plannedOrigin: Place?
    /// Нижня панель згорнута до рядка з часом прибуття. Запам'ятовується між запусками.
    var isPanelCollapsed: Bool {
        didSet { uiStorage.set(isPanelCollapsed, forKey: Self.panelCollapsedKey) }
    }
    /// Верхня панель згорнута до одного рядка: маневр і режим. Запам'ятовується між запусками.
    var isTopBarCompact: Bool {
        didSet { uiStorage.set(isTopBarCompact, forKey: Self.topBarCompactKey) }
    }
    /// Карта північчю догори замість повороту за напрямком руху. Запам'ятовується між запусками.
    var isNorthUp: Bool {
        didSet { uiStorage.set(isNorthUp, forKey: Self.northUpKey) }
    }
    /// Кнопки швидкості й зсуву під ліву руку (біля лівого краю). Стандартно під праву. Запам'ятовується між запусками.
    var isLeftHanded: Bool {
        didSet { uiStorage.set(isLeftHanded, forKey: Self.leftHandedKey) }
    }
    /// Орієнтири, чию довгу назву розгорнуто тапом по підпису на карті.
    var expandedLandmarkNames: Set<String> = []
    /// Скільки метрів на карті займає один значок орієнтира з підписом при поточному масштабі.
    var landmarkPinSpacing: Double = NavigationMapView.minPinSpacing
    var isDimmed = false
    private(set) var toast: String?
    private(set) var replayRunning = false

    @ObservationIgnored let session: NavigationSession
    @ObservationIgnored let settingsModel: SettingsModel
    @ObservationIgnored let savedPlaces: SavedPlacesModel
    @ObservationIgnored private let uiStorage: any KeyValueStorage
    @ObservationIgnored private var lastInteraction = Date()
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var isSceneActive = true
    @ObservationIgnored private var liveLocationSource: (any LocationSource)?
    @ObservationIgnored private var frames: FrameTicker?
    @ObservationIgnored private var positionSmoother = PositionSmoother()
    @ObservationIgnored private var headingSmoother = HeadingSmoother()
    /// Висота камери на екрані, поки вона після «+» чи «−» доїжджає до `followDistance`; nil, коли доїхала.
    @ObservationIgnored private var zoomDistance: CLLocationDistance?
    @ObservationIgnored private var lastFrame: Date?
    /// Орієнтири, чиї значки зараз на карті: при наступному виборі вони лишаються.
    @ObservationIgnored private var shownPins: Set<String> = []
    /// Висота стеження на початку щипка.
    @ObservationIgnored private var pinchStartDistance: CLLocationDistance?
    /// За цей дотик був щипок: тоді зсув пальців не вимикає стеження.
    @ObservationIgnored private var pinchedDuringTouch = false
    /// Камера зараз: з неї починається перетягування, що вимкнуло стеження.
    @ObservationIgnored private var currentCamera: MapCamera?
    /// Скільки метрів землі в одній точці посередині екрана, вбік і вгору: з нахилом камери вони різні.
    @ObservationIgnored var centerScale = (across: 1.0, along: 1.0)
    /// Перетягування, що вимкнуло стеження: камера і масштаб на його початку.
    @ObservationIgnored private var panStart: (camera: MapCamera, across: Double, along: Double)?
    /// Поки камера плавно повертається до позиції, кадри її не перебивають.
    @ObservationIgnored private var followAnimationUntil = Date.distantPast
    /// У стеженні почався жест MapKit (щипок, тап двома пальцями): кадри не пишуть камеру, доки вона не зупиниться.
    @ObservationIgnored private var mapKitGestureSince: Date?
    @ObservationIgnored private var lastCameraChange = Date.distantPast

    /// Камера в режимі стеження.
    static let defaultFollowDistance: CLLocationDistance = 900
    static let followDistanceRange: ClosedRange<CLLocationDistance> = 80...60_000
    /// За скільки секунд висота після «+» чи «−» проходить дві третини шляху: часті тапи камера доганяє швидше, а не стрибками.
    static let zoomTimeConstant: TimeInterval = 0.12
    static let followAnimation: TimeInterval = 0.35
    /// Жест MapKit у стеженні скінчився, коли камера стоїть стільки секунд.
    static let gestureIdle: TimeInterval = 0.4
    static let followPitch: Double = 40

    static let panelCollapsedKey = "ui.controlPanelCollapsed"
    static let topBarCompactKey = "ui.topBarCompact"
    static let northUpKey = "ui.northUp"
    static let followDistanceKey = "ui.followDistance"
    static let leftHandedKey = "ui.leftHanded"

    init(session: NavigationSession, settingsModel: SettingsModel, savedPlaces: SavedPlacesModel, uiStorage: any KeyValueStorage) {
        self.session = session
        self.settingsModel = settingsModel
        self.savedPlaces = savedPlaces
        self.uiStorage = uiStorage
        self.isPanelCollapsed = uiStorage.bool(forKey: Self.panelCollapsedKey) ?? false
        self.isTopBarCompact = uiStorage.bool(forKey: Self.topBarCompactKey) ?? false
        self.isNorthUp = uiStorage.bool(forKey: Self.northUpKey) ?? false
        self.isLeftHanded = uiStorage.bool(forKey: Self.leftHandedKey) ?? false
        self.followDistance = uiStorage.double(forKey: Self.followDistanceKey).map(Self.clampFollow) ?? Self.defaultFollowDistance
    }

    var settings: NavigationSettings { settingsModel.settings }

    /// Масштаб карти змінився: значки орієнтирів тримаються щонайменше за `pinSpacingPoints` точок один від одного.
    /// Значки орієнтирів на карті. Ті, що вже показані, лишаються, доки не зостануться позаду.
    func landmarkPins(along: Double, priority: [Landmark]) -> [Landmark] {
        let pins = LandmarkSelector.pins(
            session.visibleLandmarks, along: along, spacing: landmarkPinSpacing,
            maxCount: NavigationMapView.maxPins, priority: priority, sticky: shownPins
        )
        shownPins = Set(pins.map(\.id))
        return pins
    }

    func mapScaleChanged(metersPerPoint: Double) {
        let spacing = max(NavigationMapView.minPinSpacing, metersPerPoint * NavigationMapView.pinSpacingPoints)
        // Лише помітна зміна масштабу, щоб не перебирати значки на кожному кадрі.
        if abs(spacing - landmarkPinSpacing) > landmarkPinSpacing * 0.15 { landmarkPinSpacing = spacing }
    }

    func start() {
        guard loopTask == nil else { return }
        session.startTracking()
        let frames = FrameTicker { [weak self] in self?.frame() }
        frames.start()
        self.frames = frames
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.session.tick()
                self.afterTick()
                try? await Task.sleep(for: .seconds(self.session.settings[.updateInterval]))
            }
        }
    }

    private func afterTick() {
        updateIdleTimer()
        // Без маршруту позиція це просто точка GPS раз на секунду: камера доїжджає до неї за той самий час.
        if isFollowing, mapKitGestureSince == nil, zoomDistance == nil, session.engine.route == nil, let position = session.position {
            withAnimation(.linear(duration: min(1, session.settings[.updateInterval]))) {
                camera = .camera(followCamera(at: position))
            }
        }
        if settings[.dimEnabled], session.isNavigating, !isDimmed,
           Date().timeIntervalSince(lastInteraction) >= settings[.dimAfter] {
            isDimmed = true
        }
        if let notice = session.notice {
            showToast(notice.text)
            session.clearNotice()
        }
    }

    /// Кадр екрана: плавна позиція і курс між оновленнями рушія; у стеженні камера щокадру за ними.
    /// MapKit починає власний щипок чи перетягування, лише коли камера в мить дотику стоїть, тож у стеженні
    /// щипок обробляє `followPinchChanged`, а перетягування стеження вимикає (`mapDragChanged`).
    private func frame() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastFrame ?? now), 0.1)
        lastFrame = now
        if let motion = session.motion(at: now), let route = session.engine.route {
            let along = positionSmoother.update(motion, now: now)
            let heading = headingSmoother.update(route.polyline.bearing(at: along), now: now)
            // Пишемо лише зміни: інакше карта перебудовувалась би щокадру і тоді, коли точка стоїть.
            if displayAlong != along { displayAlong = along }
            if displayHeading != heading { displayHeading = heading }
        } else if displayAlong != nil {
            positionSmoother.reset()
            headingSmoother.reset()
            displayAlong = nil
            displayHeading = nil
        }
        // Масштаб жестом MapKit: камеру не пишемо, інакше висота стеження перебивала б його анімацію.
        if isFollowing, mapKitGestureSince == nil, camera.positionedByUser, pinchStartDistance == nil {
            mapKitGestureSince = now
        }
        if let since = mapKitGestureSince, now.timeIntervalSince(max(since, lastCameraChange)) >= Self.gestureIdle {
            mapKitGestureSince = nil
            // Стежимо далі з новою висотою, а не повертаємо стару.
            if isFollowing {
                if let cameraDistance { followDistance = Self.clampFollow(cameraDistance) }
                follow()
            }
        }
        // Висота після «+» і «−» доганяє ціль за експонентою (у логарифмі, бо масштаб множиться).
        if let zoom = zoomDistance {
            let next = followDistance * pow(zoom / followDistance, exp(-dt / Self.zoomTimeConstant))
            zoomDistance = abs(next / followDistance - 1) < 0.003 || !isFollowing ? nil : next
        }
        // Без маршруту камеру веде `afterTick`, але висоту, що змінюється, теж пишуть кадри.
        if isFollowing, mapKitGestureSince == nil, session.engine.route != nil || zoomDistance != nil,
           now >= followAnimationUntil, let position = displayPosition {
            let target = followCamera(at: position)
            if camera.camera != target { camera = .camera(target) }
        }
    }

    /// Моя позиція на екрані: на маршруті плавна, без маршруту остання точка GPS.
    var displayPosition: Coordinate? {
        guard let along = displayAlong, let route = session.engine.route else { return session.position }
        return route.polyline.coordinate(at: along)
    }

    private func followCamera(at position: Coordinate) -> MapCamera {
        MapCamera(
            centerCoordinate: position.cl,
            distance: zoomDistance ?? followDistance,
            heading: isNorthUp ? 0 : displayHeading ?? session.heading ?? 0,
            pitch: Self.followPitch
        )
    }

    /// Плавно повернути камеру до позиції, далі за нею йдуть кадри.
    func follow() {
        guard let position = displayPosition else { return }
        followAnimationUntil = Date().addingTimeInterval(Self.followAnimation)
        withAnimation(.easeInOut(duration: Self.followAnimation)) {
            camera = .camera(followCamera(at: position))
        }
    }

    /// У стеженні MapKit лишається тільки масштабування: камера весь час рухається, і перетягування MapKit
    /// однаково не почалось би, а лише забирало б дотики. Перетягування обробляє `mapDragChanged`.
    var mapInteractions: MapInteractionModes { isFollowing ? [.zoom] : .all }

    /// Камера змінилась (кадр стеження, жест MapKit або щипок у стеженні).
    func cameraChanged(_ camera: MapCamera) {
        currentCamera = camera
        cameraDistance = camera.distance
        lastCameraChange = Date()
    }

    /// «+» і «−» у стеженні: висота камери в `factor` разів, стеження лишається.
    /// Камера доїжджає до нової висоти щокадру, а не анімацією MapKit: нова анімація переривала б попередню стрибком.
    func zoomFollow(by factor: Double) {
        if zoomDistance == nil { zoomDistance = followDistance }
        followDistance = Self.clampFollow(followDistance * factor)
    }

    /// Щипок у стеженні: `scale` більше 1 наближає, менше віддаляє; стеження лишається.
    func followPinchChanged(_ scale: CGFloat) {
        guard isFollowing, scale > 0 else { return }
        let start = pinchStartDistance ?? followDistance
        pinchStartDistance = start
        pinchedDuringTouch = true
        zoomDistance = nil
        followDistance = Self.clampFollow(start / Double(scale))
    }

    func followPinchEnded() {
        pinchStartDistance = nil
    }

    /// Перетягування карти в стеженні вимикає стеження, і карта одразу їде під пальцем. Далі карта звичайна,
    /// з жестами MapKit, до «Центрувати». Під час щипка пальці теж зсуваються: тоді стеження лишається.
    func mapDragChanged(_ translation: CGSize) {
        if panStart == nil {
            guard isFollowing, !pinchedDuringTouch, let currentCamera else { return }
            isFollowing = false
            mapKitGestureSince = nil
            panStart = (currentCamera, centerScale.across, centerScale.along)
        }
        guard let panStart else { return }
        // Палець униз відкриває те, що вище на екрані, тобто попереду за курсом камери; праворуч відкриває те, що ліворуч.
        var camera = panStart.camera
        let start = Coordinate(camera.centerCoordinate)
        let ahead = Geo.destination(from: start, bearing: camera.heading, distance: Double(translation.height) * panStart.along)
        let shifted = Geo.destination(from: ahead, bearing: camera.heading - 90, distance: Double(translation.width) * panStart.across)
        camera.centerCoordinate = shifted.cl
        self.camera = .camera(camera)
    }

    func mapDragEnded() {
        panStart = nil
        pinchedDuringTouch = false
    }

    static func clampFollow(_ distance: CLLocationDistance) -> CLLocationDistance {
        min(max(distance, followDistanceRange.lowerBound), followDistanceRange.upperBound)
    }

    /// Прокласти маршрут до місця від вибраної точки відправлення або від моєї позиції.
    /// `remember`: додати місце до останніх адрес у пошуку (точку з карти не додаємо).
    func go(to place: Place, remember: Bool = true) async {
        isFollowing = true
        await session.buildRoute(to: place, from: plannedOrigin)
        if session.routeError == nil {
            plannedOrigin = nil
            if remember { savedPlaces.store(place, as: .recent) }
        }
        // Точка чекає на старті: кнопка «Далі» має бути на виду, навіть якщо панель згорнута.
        if session.isNavigating, session.engine.reckoner.isPaused { isPanelCollapsed = false }
    }

    /// «Я тут» з картки точки: позиція на маршруті навпроти неї.
    func moveHere(_ place: Place) {
        guard session.moveHere(place.coordinate) else { return }
        pendingDestination = nil
    }

    /// «Маршрут звідси»: я звернув не туди. Маршрут від точки до того самого пункту призначення,
    /// камера знову стежить за позицією на його початку.
    func rebuildRoute(from place: Place) {
        pendingDestination = nil
        Task {
            await session.rebuildRoute(from: place)
            if session.routeError == nil { recenter() }
        }
    }

    /// «Перейти на GPS»: одразу, якщо GPS придатний, інакше питаємо, чи все одно вести за GPS.
    func requestGPS() {
        if session.gpsAvailability == .usable {
            session.selectGPS()
        } else {
            showModeOptions = true
        }
    }

    /// «Центрувати»: знову стежити за позицією з тим масштабом, який зараз на карті.
    func recenter() {
        zoomDistance = nil
        if let cameraDistance { followDistance = Self.clampFollow(cameraDistance) }
        isFollowing = true
        follow()
    }

    /// Тап по підпису з довгою назвою: показати повну назву або знову скорочену.
    func toggleLandmarkName(_ id: String) {
        if expandedLandmarkNames.remove(id) == nil { expandedLandmarkNames.insert(id) }
    }

    /// Компас: північ зверху або за напрямком руху. Карта одразу повертається до моєї позиції.
    func toggleNorthUp() {
        isNorthUp.toggle()
        recenter()
    }

    // MARK: Екран

    /// Будь-який дотик знімає затемнення і відкладає наступне.
    func registerInteraction() {
        lastInteraction = Date()
        if isDimmed { isDimmed = false }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        isSceneActive = phase == .active
        // У фоні кадри не малюються: не витрачаємо батарею.
        if isSceneActive { frames?.start() } else { frames?.stop() }
        updateIdleTimer()
        if phase == .background { session.persist() }
    }

    /// Екран не гасне, поки йде навігація; у фоні і після завершення повертаємо системну поведінку.
    func updateIdleTimer() {
        let keepOn = session.isNavigating && settings[.keepScreenOn] && isSceneActive
        if UIApplication.shared.isIdleTimerDisabled != keepOn {
            UIApplication.shared.isIdleTimerDisabled = keepOn
        }
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func endNavigation() {
        stopReplay()
        session.endNavigation()
        updateIdleTimer()
        isDimmed = false
    }

    // MARK: Режим тестування

    func startReplay(options: ReplayOptions) {
        guard let track = BundledFixtures.track(), let route = BundledFixtures.route() else {
            showToast("Немає записаного GPX-треку в бандлі")
            return
        }
        if liveLocationSource == nil { liveLocationSource = session.locationSource }
        let start = Date()
        let source = ScriptedLocationSource(plan: ReplayPlanner.plan(track: track, options: options, start: start), planStart: start)
        session.replaceLocationSource(source)
        if session.engine.route?.id != route.id {
            session.begin(route: route, destination: BundledFixtures.destination(for: route))
        }
        replayRunning = true
        isFollowing = true
        showToast("Програвання GPX запущено")
    }

    func stopReplay() {
        guard replayRunning else { return }
        if let live = liveLocationSource { session.replaceLocationSource(live) }
        liveLocationSource = nil
        replayRunning = false
    }
}




