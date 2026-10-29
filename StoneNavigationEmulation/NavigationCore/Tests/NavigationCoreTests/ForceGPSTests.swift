import Foundation
import Testing
@testable import NavigationCore

@Suite("Перехід на GPS за бажанням водія")
@MainActor
struct ForceGPSTests {
    @Test("Стан GPS: придатний, неточний, невідома точність, застарілий, немає сигналу")
    func availability() {
        var h = EngineHarness()
        #expect(h.engine.gpsAvailability(at: h.now) == .noSignal)
        h.gps(along: 0)
        #expect(h.engine.gpsAvailability(at: h.now) == .usable)
        h.advance(4)
        #expect(h.engine.gpsAvailability(at: h.now) == .stale(age: 4))
        h.gps(along: 40, accuracy: 150)
        #expect(h.engine.gpsAvailability(at: h.now) == .poorAccuracy(150))
        h.gps(along: 40, accuracy: -1)
        #expect(h.engine.gpsAvailability(at: h.now) == .poorAccuracy(nil))
    }

    @Test("«Все одно GPS» при поганій точності: позиція йде за GPS, сама на розрахункову не переходить")
    func forcedGPSFollowsPoorFixes() {
        var h = EngineHarness()
        h.gps(along: 100)
        h.advance(1)
        h.gps(along: 110, accuracy: 150)
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.modeReason == .poorAccuracy)

        h.engine.forceGPS(now: h.now)
        #expect(h.engine.mode == .gps)
        #expect(h.engine.control == .manualGPS)
        #expect(h.engine.modeReason == .userForcedGPS)
        #expect(abs(h.engine.along - 110) < 0.5)
        #expect(h.engine.drainEvents().contains(.modeChanged(from: .deadReckoning, to: .gps, reason: .userForcedGPS)))

        // Погана точність, стрибок, помилка і тиша не повертають розрахункову.
        h.advance(1)
        h.gps(along: 120, accuracy: 300)
        #expect(abs(h.engine.along - 120) < 0.5)
        h.advance(1)
        h.gps(along: 1700)
        #expect(abs(h.engine.along - 1700) < 0.5)
        h.send(.error(.locationUnknown))
        h.advance(10)
        #expect(h.engine.mode == .gps)
        #expect(abs(h.engine.along - 1700) < 0.5, "без розрахунку точка чекає наступної точки GPS")
    }

    @Test("Старіша за останню точка GPS у ручному режимі ігнорується")
    func forcedGPSIgnoresOutOfOrderFixes() {
        var h = EngineHarness()
        h.gps(along: 100)
        h.engine.forceGPS(now: h.now)
        h.advance(2)
        h.gps(along: 200)
        let old = LocationFix.good(TestRoute.point(along: 150), at: h.now.addingTimeInterval(-5))
        h.send(.fix(old))
        #expect(abs(h.engine.along - 200) < 0.5)
    }

    @Test("Без жодної точки «Все одно GPS» тримає позицію і бере першу точку, що прийде")
    func forcedGPSWithoutSignalWaitsForFirstFix() {
        var h = EngineHarness(along: 300)
        h.engine.selectDeadReckoning(now: h.now)
        h.advance(5)
        #expect(abs(h.engine.along - 350) < 0.01)
        #expect(h.engine.gpsAvailability(at: h.now) == .noSignal)

        h.engine.forceGPS(now: h.now)
        #expect(h.engine.mode == .gps)
        h.advance(10)
        #expect(abs(h.engine.along - 350) < 0.01)
        h.gps(along: 500, accuracy: 80)
        #expect(abs(h.engine.along - 500) < 0.5)
    }

    @Test("З ручного GPS «Автоматичне перемикання» знову вмикає розрахункову при поганій точці")
    func backToAutomatic() {
        var h = EngineHarness()
        h.gps(along: 100)
        h.engine.forceGPS(now: h.now)
        h.advance(1)
        h.gps(along: 110, accuracy: 150)
        #expect(h.engine.mode == .gps)

        h.engine.selectGPS(now: h.now)
        #expect(h.engine.mode == .gps)
        #expect(h.engine.control == .automatic)
        h.advance(1)
        h.gps(along: 120, accuracy: 150)
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.modeReason == .poorAccuracy)
    }

    @Test("З ручного GPS «Розрахункова позиція» працює як звичайний ручний перемикач")
    func forcedGPSToManualDeadReckoning() {
        var h = EngineHarness()
        h.gps(along: 100)
        h.engine.forceGPS(now: h.now)
        h.engine.selectDeadReckoning(now: h.now)
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.control == .manualDeadReckoning)
    }

    @Test("У сесії: журнал Mode і повідомлення на екрані")
    func sessionLogsAndNotifies() {
        let h = SessionHarness()
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.gps(TestRoute.point(along: 0))
        h.advance(1)
        h.location.send(.error(.locationUnknown))
        h.advance(5)
        #expect(h.session.gpsAvailability == .stale(age: 6))
        h.session.forceGPS()
        #expect(h.session.engine.mode == .gps)
        #expect(h.log.messages.contains { $0.contains("Режим: Розрахункова позиція → GPS [deadReckoning->gps], причина: GPS увімкнено вручну [userForcedGPS]") })
        #expect(h.session.notice?.text == "Ведемо за GPS. Сам на розрахункову не перейде, доки не перемкнете")
    }

    @Test("Ручний GPS має перевагу над стартом із вибраної точки")
    func forcedGPSWinsOverChosenStart() async {
        let h = SessionHarness()
        h.gps(Geo.destination(from: TestRoute.start, bearing: 200, distance: 3000), accuracy: 200)
        h.session.forceGPS()
        await h.session.buildRoute(to: Place(name: "Фініш", coordinate: TestRoute.end), from: Place(name: "Старт", coordinate: TestRoute.start))
        #expect(h.session.engine.mode == .gps)
        #expect(h.session.engine.control == .manualGPS)
        #expect(!h.session.engine.reckoner.isPaused)
        #expect(h.log.messages.contains("Старт із вибраної точки «Старт»: GPS увімкнено вручну, ведемо за GPS"))
    }
}
