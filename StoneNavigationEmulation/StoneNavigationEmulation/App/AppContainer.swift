import Foundation
import NavigationCore

/// Збирає залежності: справжні порти або фейкові для сценарію. Жодних синглтонів у логіці:
/// усе передається в NavigationSession і далі в екрани через Environment.
@MainActor
final class AppContainer {
    let session: NavigationSession
    let settingsModel: SettingsModel
    let appModel: AppModel
    let searchModel: SearchModel
    let savedPlaces: SavedPlacesModel

    private init(session: NavigationSession, settingsModel: SettingsModel, appModel: AppModel) {
        self.session = session
        self.settingsModel = settingsModel
        self.appModel = appModel
        self.savedPlaces = appModel.savedPlaces
        self.searchModel = SearchModel(places: session.placeSearch, near: { [weak session] in session?.position })
        settingsModel.onChange = { [weak session] settings in session?.apply(settings: settings) }
    }

    static func make(launch: LaunchConfiguration) -> AppContainer {
        let bundleID = Bundle.main.bundleIdentifier ?? "StoneNavigationEmulation"
        let log = OSModeLog(subsystem: bundleID)
        if let scenario = launch.scenario {
            return makeScenario(scenario, launch: launch, log: log)
        }
        return makeLive(launch: launch, log: log)
    }

    private static func makeLive(launch: LaunchConfiguration, log: OSModeLog) -> AppContainer {
        let storage = UserDefaultsStorage(defaults: .standard)
        let repository = SettingsRepository(storage: storage)
        let store = FileSessionStore()
        if launch.resetState {
            store.clear()
            repository.reset()
            storage.removeValue(forKey: AppModel.panelCollapsedKey)
            storage.removeValue(forKey: AppModel.topBarCompactKey)
            storage.removeValue(forKey: AppModel.northUpKey)
            storage.removeValue(forKey: AppModel.leftHandedKey)
            storage.removeValue(forKey: AppModel.followDistanceKey)
            SavedPlacesRepository(storage: storage).clear()
        }
        let ports = NavigationPorts(
            location: CoreLocationSource(),
            motion: CoreMotionSource(),
            routes: MapKitRouteProvider(),
            places: CountryFilteredPlaceSearch(base: MapKitPlaceSearch()),
            speech: SystemSpeechOutput(),
            clock: SystemClock(),
            log: log,
            store: store
        )
        let settingsModel = SettingsModel(repository: repository)
        let session = NavigationSession(ports: ports, settings: settingsModel.settings, restoreState: !launch.resetState)
        if launch.loadRoute == "test", let route = BundledFixtures.route() {
            session.begin(route: route, destination: BundledFixtures.destination(for: route))
        }
        let appModel = AppModel(
            session: session,
            settingsModel: settingsModel,
            savedPlaces: SavedPlacesModel(repository: SavedPlacesRepository(storage: storage)),
            uiStorage: storage
        )
        return AppContainer(session: session, settingsModel: settingsModel, appModel: appModel)
    }

    private static func makeScenario(_ scenario: ScenarioName, launch: LaunchConfiguration, log: OSModeLog) -> AppContainer {
        guard let route = BundledFixtures.route(), let track = BundledFixtures.track() else {
            fatalError("У бандлі немає фікстур Fixtures/test_route.json і test_track.gpx")
        }
        let start = Date()
        let setup = Scenarios.setup(for: scenario, track: track, route: route, start: start)
        let destination = BundledFixtures.destination(for: route)
        let ports = NavigationPorts(
            location: ScriptedLocationSource(plan: setup.plan, planStart: start),
            motion: launch.motion.map { FixedMotionSource(activity: $0) } ?? FakeMotionSource(),
            routes: FakeRouteProvider(result: .success(route)),
            places: CountryFilteredPlaceSearch(base: FakePlaceSearch(
                candidates: BundledFixtures.pois() + Scenarios.extraLandmarks(for: scenario, route: route, plan: setup.plan),
                places: [destination, BundledFixtures.origin(for: route)] + BundledFixtures.blockedPlaces
            )),
            speech: FakeSpeechOutput(),
            clock: SystemClock(),
            log: log,
            store: InMemorySessionStore()
        )
        let settingsModel = SettingsModel(repository: SettingsRepository(storage: InMemoryKeyValueStorage()))
        for (key, value) in launch.settings { settingsModel.set(key, value) }
        let session = NavigationSession(ports: ports, settings: settingsModel.settings, restoreState: false)
        session.begin(route: route, destination: destination)
        let uiStorage = InMemoryKeyValueStorage()
        let appModel = AppModel(
            session: session,
            settingsModel: settingsModel,
            savedPlaces: SavedPlacesModel(repository: SavedPlacesRepository(storage: uiStorage)),
            uiStorage: uiStorage
        )
        appModel.showSettings = setup.opensSettings
        log.log("Сценарій -scenario \(scenario.rawValue): фейкова геолокація, записаний маршрут")
        return AppContainer(session: session, settingsModel: settingsModel, appModel: appModel)
    }
}
