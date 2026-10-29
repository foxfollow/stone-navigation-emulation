import Foundation
import Testing
@testable import NavigationCore

@Suite("Розрахункова позиція з фейковим годинником")
struct DeadReckoningTests {
    @Test("Після втрати GPS точка рухається зі швидкістю маршруту за фейковим годинником")
    func movesWithFakeClock() {
        var h = EngineHarness()
        h.gps(along: 0)
        h.advance(1, tick: false)
        h.loseGPS()
        // Екстраполяція: 1 с після останньої доброї точки × 10 м/с.
        #expect(h.engine.mode == .deadReckoning)
        #expect(abs(h.engine.along - 10) < 0.01)

        h.advance(10)
        #expect(abs(h.engine.along - 110) < 0.01)
        let expected = Geo.destination(from: TestRoute.start, bearing: 0, distance: 110)
        #expect(Geo.distance(h.engine.position(at: h.now)!, expected) < 0.5)
    }

    @Test("Точка проходить поворот маршруту і зупиняється в кінці")
    func followsRouteAroundCorner() {
        var h = EngineHarness()
        h.loseGPS()
        h.advance(150)
        #expect(abs(h.engine.along - 1500) < 0.01)
        #expect(abs(h.engine.heading(at: h.now)! - 90) < 0.5)
        h.advance(1000)
        #expect(h.engine.along == h.engine.routeLength)
        #expect(h.engine.hasArrived)
    }

    @Test("Пріоритет швидкості: маршрут, потім GPS, потім стандартна з Налаштувань")
    func speedPriority() {
        var withRoute = EngineHarness()
        withRoute.loseGPS()
        #expect(withRoute.engine.speedInfo.source == .route)
        #expect(withRoute.engine.speedInfo.speed == 10)

        var withGPS = EngineHarness(route: TestRoute.make(expectedTravelTime: nil))
        withGPS.gps(along: 0, speed: 15)
        withGPS.advance(1, tick: false)
        withGPS.loseGPS()
        #expect(withGPS.engine.speedInfo.source == .gps)
        #expect(withGPS.engine.speedInfo.speed == 15)

        var standard = EngineHarness(route: TestRoute.make(expectedTravelTime: nil))
        standard.loseGPS()
        #expect(standard.engine.speedInfo.source == .standard)
        #expect(abs(standard.engine.speedInfo.speed - 50 / 3.6) < 0.001)
        standard.advance(36)
        #expect(abs(standard.engine.along - 500) < 0.01)
    }

    @Test("Ручна швидкість діє, доки не натиснуто Скинути")
    func manualSpeedUntilReset() {
        var h = EngineHarness()
        h.loseGPS()
        h.engine.increaseSpeed()
        #expect(h.engine.speedInfo.source == .manual)
        #expect(abs(h.engine.speedInfo.speed - (10 + 5 / 3.6)) < 0.001)
        h.engine.decreaseSpeed()
        h.engine.decreaseSpeed()
        #expect(abs(h.engine.speedInfo.speed - (10 - 5 / 3.6)) < 0.001)
        h.advance(60)
        #expect(h.engine.speedInfo.source == .manual)
        h.engine.resetSpeed()
        #expect(h.engine.speedInfo.source == .route)
        #expect(h.engine.speedInfo.speed == 10)
    }

    @Test("Крок кнопок швидкості береться з Налаштувань")
    func speedStepFromSettings() {
        var settings = NavigationSettings()
        settings[.speedStepKmh] = 18
        var h = EngineHarness(settings: settings)
        h.loseGPS()
        h.engine.increaseSpeed()
        #expect(abs(h.engine.speedInfo.speed - 15) < 0.001)
    }

    @Test("Пауза і стоянка зупиняють точку")
    func pauseAndStationary() {
        var h = EngineHarness()
        h.loseGPS()
        h.engine.togglePause()
        h.advance(30)
        #expect(h.engine.along == 0)
        h.engine.togglePause()
        h.advance(10)
        #expect(abs(h.engine.along - 100) < 0.01)

        h.engine.handleActivity(.stationary)
        h.advance(30)
        #expect(abs(h.engine.along - 100) < 0.01)
        h.engine.handleActivity(.automotive)
        h.advance(10)
        #expect(abs(h.engine.along - 200) < 0.01)
    }

    @Test("«Рушити» знімає стоянку за датчиками, доки вони не побачать рух")
    func ignoreStationary() {
        var h = EngineHarness()
        h.loseGPS()
        h.engine.handleActivity(.stationary)
        h.advance(10)
        #expect(h.engine.along == 0)
        h.engine.ignoreStationary()
        #expect(h.engine.isStationaryIgnored)
        // Телефон лежить: датчики й далі кажуть «стоянка», а точка їде.
        h.engine.handleActivity(.stationary)
        h.advance(10)
        #expect(abs(h.engine.along - 100) < 0.01)
        // Датчики побачили рух: наступна справжня стоянка знову зупиняє точку.
        h.engine.handleActivity(.automotive)
        #expect(!h.engine.isStationaryIgnored)
        h.engine.handleActivity(.stationary)
        h.advance(10)
        #expect(abs(h.engine.along - 100) < 0.01)
    }

    @Test("«Далі» після паузи на стоянці одразу рушає")
    func resumeWhileStationary() {
        var h = EngineHarness()
        h.loseGPS()
        h.engine.handleActivity(.stationary)
        h.engine.togglePause()
        h.advance(10)
        h.engine.togglePause()
        #expect(!h.engine.reckoner.isPaused)
        #expect(!h.engine.reckoner.isStationary)
        h.advance(10)
        #expect(abs(h.engine.along - 100) < 0.01)
    }

    @Test("Вперед і Назад зсувають точку на крок з Налаштувань і не виходять за маршрут")
    func nudge() {
        var h = EngineHarness(along: 300)
        h.loseGPS()
        h.engine.moveForward(now: h.now)
        #expect(abs(h.engine.along - 350) < 0.01)
        h.engine.moveBack(now: h.now)
        h.engine.moveBack(now: h.now)
        #expect(abs(h.engine.along - 250) < 0.01)

        var settings = NavigationSettings()
        settings[.shiftStepMeters] = 500
        h.engine.apply(settings: settings)
        h.engine.moveBack(now: h.now)
        #expect(h.engine.along == 0)
        for _ in 0..<5 { h.engine.moveForward(now: h.now) }
        #expect(h.engine.along == h.engine.routeLength)
    }

    @Test("Тап по маршруту в режимі GPS вмикає ручну розрахункову позицію")
    func tapInGPSMode() {
        var h = EngineHarness()
        h.gps(along: 100)
        h.engine.setPosition(along: 700, now: h.now, reason: .tapOnRoute)
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.control == .manualDeadReckoning)
        #expect(h.engine.modeReason == .userMovedPosition)
        #expect(abs(h.engine.along - 700) < 0.01)
    }

    @Test("Пропущений час після призупинення застосунку теж проїжджається")
    func catchesUpAfterSuspension() {
        var h = EngineHarness()
        h.loseGPS()
        h.advance(1)
        h.advance(120)
        #expect(abs(h.engine.along - 1210) < 0.01)
    }

    @Test("Таймер «без GPS» рахує від останньої доброї точки")
    func timerWithoutGPS() {
        var h = EngineHarness()
        h.gps(along: 0)
        h.advance(4)
        #expect(h.engine.mode == .deadReckoning)
        h.advance(10)
        #expect(h.engine.timeWithoutGPS(at: h.now) == 14)
    }
}
