import Foundation
import Testing
@testable import NavigationCore

@Suite("Вибрана точка відправлення")
@MainActor
struct ChosenStartTests {
    let origin = Place(name: "Старт", coordinate: TestRoute.start)
    let destination = Place(name: "Фініш", coordinate: TestRoute.end)

    @Test("Маршрут запитується від вибраної точки, а не від GPS")
    func requestsRouteFromChosenOrigin() async throws {
        let h = SessionHarness()
        let elsewhere = Geo.destination(from: TestRoute.start, bearing: 200, distance: 3000)
        h.gps(elsewhere)
        await h.session.buildRoute(to: destination, from: origin)
        let request = try #require(h.routes.requests.last)
        #expect(request.origin == origin.coordinate)
        #expect(request.destination == destination.coordinate)
        #expect(h.session.isNavigating)
    }

    @Test("Без вибраної точки маршрут, як і раніше, від моєї позиції")
    func defaultsToMyPosition() async throws {
        let h = SessionHarness()
        let here = TestRoute.point(along: 0, offset: 20)
        h.gps(here)
        await h.session.buildRoute(to: destination)
        let request = try #require(h.routes.requests.last)
        #expect(request.origin == here)
    }

    @Test("GPS далеко від старту: розрахункова позиція чекає на старті, доки не натиснути «Далі»")
    func farGPSStartsPausedAtChosenPoint() async {
        let h = SessionHarness()
        h.gps(Geo.destination(from: TestRoute.start, bearing: 200, distance: 3000))
        await h.session.buildRoute(to: destination, from: origin)

        #expect(h.session.engine.mode == .deadReckoning)
        #expect(h.session.engine.modeReason == .chosenStart)
        #expect(h.session.engine.along == 0)
        #expect(h.session.engine.reckoner.isPaused)
        #expect(h.session.notice?.text == "Старт: Старт. Натисніть «Далі», коли рушите")
        #expect(h.log.messages.contains { $0.contains("причина: старт із вибраної точки [chosenStart], позиція 0 м") })

        // Авто ще стоїть: точка не рухається.
        h.advance(10)
        #expect(h.session.engine.along == 0)
        #expect(h.session.engine.timeWithoutGPS(at: h.session.now) == 10)

        // «Далі»: їде із середньою швидкістю маршруту, 10 м/с.
        h.session.togglePause()
        h.advance(10)
        #expect(abs(h.session.engine.along - 100) < 0.01)
    }

    @Test("«Перейти на GPS» зі старту на паузі знімає паузу: після нової втрати GPS точка їде")
    func switchingToGPSClearsChosenStartPause() async {
        let h = SessionHarness()
        h.gps(Geo.destination(from: TestRoute.start, bearing: 200, distance: 3000))
        await h.session.buildRoute(to: destination, from: origin)
        #expect(h.session.engine.reckoner.isPaused)

        h.gps(TestRoute.point(along: 200))
        h.session.selectGPS()
        #expect(h.session.engine.mode == .gps)
        #expect(!h.session.engine.reckoner.isPaused)

        h.location.send(.error(.locationUnknown))
        h.advance(10)
        #expect(h.session.engine.along > 250)
    }

    @Test("Без GPS теж стартуємо з вибраної точки на паузі")
    func noGPSStartsPaused() async {
        let h = SessionHarness()
        await h.session.buildRoute(to: destination, from: origin)
        #expect(h.session.engine.mode == .deadReckoning)
        #expect(h.session.engine.along == 0)
        #expect(h.session.engine.reckoner.isPaused)
    }

    @Test("GPS уже без сигналу: позиція переходить на старт нового маршруту і чекає")
    func alreadyDeadReckoningMovesToChosenStart() async {
        let h = SessionHarness()
        h.session.begin(route: TestRoute.make(), destination: destination)
        h.gps(TestRoute.point(along: 300))
        h.location.send(.error(.locationUnknown))
        #expect(h.session.engine.modeReason == .locationError)
        h.advance(20)
        #expect(h.session.engine.along > 300)

        await h.session.buildRoute(to: destination, from: origin)
        #expect(h.session.engine.mode == .deadReckoning)
        #expect(h.session.engine.modeReason == .locationError)
        #expect(h.session.engine.along == 0)
        #expect(h.session.engine.reckoner.isPaused)
    }

    @Test("Свіжий GPS поруч зі стартом: лишаємось на GPS без паузи")
    func nearbyGPSKeepsGPSMode() async {
        let h = SessionHarness()
        h.gps(TestRoute.point(along: 40, offset: 10))
        await h.session.buildRoute(to: destination, from: origin)
        #expect(h.session.engine.mode == .gps)
        #expect(!h.session.engine.reckoner.isPaused)
        #expect(h.log.messages.contains("Старт із вибраної точки «Старт»: GPS поруч, ведемо за GPS"))
    }

    @Test("Межа «поруч» це налаштування межі підміни")
    func nearnessFollowsSpoofDistanceSetting() async {
        var settings = NavigationSettings()
        settings[.spoofDistance] = 100
        let h = SessionHarness(settings: settings)
        h.gps(TestRoute.point(along: 300))
        await h.session.buildRoute(to: destination, from: origin)
        #expect(h.session.engine.mode == .deadReckoning)
        #expect(h.session.engine.reckoner.isPaused)

        let relaxed = SessionHarness()
        relaxed.gps(TestRoute.point(along: 300))
        await relaxed.session.buildRoute(to: destination, from: origin)
        #expect(relaxed.session.engine.mode == .gps)
    }

    @Test("Після старту з вибраної точки далекий GPS не забирає позицію сам: питає водія")
    func farGPSLaterAsksBeforeSwitching() async {
        let h = SessionHarness()
        let elsewhere = Geo.destination(from: TestRoute.start, bearing: 200, distance: 3000)
        h.gps(elsewhere)
        await h.session.buildRoute(to: destination, from: origin)
        for _ in 0...6 {
            h.advance(1)
            h.gps(elsewhere)
        }
        #expect(h.session.engine.mode == .deadReckoning)
        #expect(h.session.engine.along == 0)
        #expect(h.session.engine.spoofPrompt != nil)
    }
}
