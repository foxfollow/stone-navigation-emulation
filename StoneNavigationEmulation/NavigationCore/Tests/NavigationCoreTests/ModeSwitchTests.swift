import Foundation
import Testing
@testable import NavigationCore

@Suite("Вмикання розрахункового режиму")
struct ModeSwitchTests {
    @Test("Добрі точки тримають режим GPS і прив'язують позицію до дороги")
    func goodFixesKeepGPS() {
        var h = EngineHarness()
        for second in 0..<10 {
            h.gps(along: Double(second) * 10, offset: 8)
            h.advance(1)
        }
        #expect(h.engine.mode == .gps)
        #expect(abs(h.engine.along - 90) < 0.5)
        // Позиція лежить на лінії маршруту, а не на 8 м збоку.
        #expect(h.engine.route!.polyline.project(h.engine.position(at: h.now)!)!.offset < 0.5)
        #expect(h.engine.offRoute == nil)
    }

    @Test("Помилка CLLocationManager вмикає розрахунковий режим")
    func error() {
        var h = EngineHarness()
        h.gps(along: 0)
        h.send(.error(.locationUnknown))
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.modeReason == .locationError)
        #expect(h.engine.drainEvents().contains(.modeChanged(from: .gps, to: .deadReckoning, reason: .locationError)))
    }

    @Test("Застаріла точка (старша за поріг) вмикає розрахунковий режим")
    func staleFix() {
        var h = EngineHarness()
        h.gps(along: 0)
        h.advance(1, tick: false)
        let old = LocationFix.good(TestRoute.point(along: 10), at: h.now.addingTimeInterval(-3.5))
        h.send(.fix(old))
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.modeReason == .staleFix)
    }

    @Test("Точка віком у межах порогу не вмикає розрахунковий режим")
    func freshEnoughFix() {
        var h = EngineHarness()
        let fix = LocationFix.good(TestRoute.point(along: 10), at: h.now.addingTimeInterval(-2.5))
        h.send(.fix(fix))
        #expect(h.engine.mode == .gps)
    }

    @Test("Точність гірша за поріг вмикає розрахунковий режим")
    func poorAccuracy() {
        var h = EngineHarness()
        h.gps(along: 0)
        h.advance(1)
        h.gps(along: 10, accuracy: 150)
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.modeReason == .poorAccuracy)
    }

    @Test("Недійсна точність (від'ємна) теж вважається поганою")
    func invalidAccuracy() {
        var h = EngineHarness()
        h.gps(along: 0, accuracy: -1)
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.modeReason == .poorAccuracy)
    }

    @Test("Поріг точності береться з Налаштувань: 80 м це GPS при 100 і розрахунок при 50")
    func accuracyThresholdFromSettings() {
        var standard = EngineHarness()
        standard.gps(along: 0, accuracy: 80)
        #expect(standard.engine.mode == .gps)

        var strict = NavigationSettings()
        strict[.enterAccuracy] = 50
        var changed = EngineHarness(settings: strict)
        changed.gps(along: 0, accuracy: 80)
        #expect(changed.engine.mode == .deadReckoning)
    }

    @Test("Якщо точок немає довше за поріг, вмикається розрахунковий режим")
    func noFixesTimeout() {
        var h = EngineHarness()
        h.gps(along: 0)
        h.advance(3)
        #expect(h.engine.mode == .gps)
        h.advance(1)
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.modeReason == .staleFix)
        // Екстраполяція: 4 с без точок × 10 м/с.
        #expect(abs(h.engine.along - 40) < 0.01)
    }

    @Test("Без жодної точки від старту вмикається розрахунковий режим з причиною «немає точок»")
    func noFixAtAll() {
        var h = EngineHarness()
        h.advance(4)
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.modeReason == .noFix)
    }

    @Test("Поріг застарілості береться з Налаштувань")
    func staleAgeFromSettings() {
        var settings = NavigationSettings()
        settings[.staleAge] = 10
        var h = EngineHarness(settings: settings)
        h.gps(along: 0)
        h.advance(9)
        #expect(h.engine.mode == .gps)
        h.advance(2)
        #expect(h.engine.mode == .deadReckoning)
    }

    @Test("Ручний перемикач: розрахункова позиція без автоповернення і назад на GPS")
    func manualToggle() {
        var h = EngineHarness()
        h.gps(along: 100)
        h.engine.selectDeadReckoning(now: h.now)
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.control == .manualDeadReckoning)
        for _ in 0..<10 {
            h.advance(1)
            h.gps(along: h.engine.along)
        }
        #expect(h.engine.mode == .deadReckoning)
        h.engine.selectGPS(now: h.now)
        #expect(h.engine.mode == .gps)
        #expect(h.engine.control == .automatic)
        #expect(h.engine.modeReason == .userSelectedGPS)
    }

    @Test("Ручний перехід на GPS без придатної точки лишає розрахункову і повідомляє")
    func manualGPSWithoutSignal() {
        var h = EngineHarness()
        h.engine.selectDeadReckoning(now: h.now)
        _ = h.engine.drainEvents()
        h.engine.selectGPS(now: h.now)
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.control == .automatic)
        #expect(h.engine.drainEvents() == [.gpsUnavailable])
    }

    @Test("GPS далі за поріг від маршруту пропонує перебудувати маршрут")
    func offRoute() {
        var h = EngineHarness()
        h.gps(along: 300, offset: 30)
        #expect(h.engine.offRoute == nil)
        h.advance(1)
        h.gps(along: 310, offset: 80)
        #expect(h.engine.offRoute != nil)
        #expect(h.engine.mode == .gps)
        #expect(h.engine.drainEvents().contains { if case .offRoute = $0 { true } else { false } })
    }
}

@Suite("Журнал переходів режимів (категорія Mode)")
@MainActor
struct ModeLogTests {
    @Test("Сесія пише переходи GPS → розрахункова і рух точки")
    func logsTransitions() {
        let h = SessionHarness()
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.gps(TestRoute.point(along: 0))
        h.advance(1)
        h.location.send(.error(.locationUnknown))
        h.advance(5)
        h.advance(5)
        let messages = h.log.messages
        #expect(messages.contains { $0.contains("Режим: GPS → Розрахункова позиція [gps->deadReckoning]") && $0.contains("[locationError]") })
        #expect(messages.contains { $0.hasPrefix("Розрахункова позиція (рух)") })
        #expect(OSModeLog.category == "Mode")
    }
}
