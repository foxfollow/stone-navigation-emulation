import Foundation
import Testing
@testable import NavigationCore

@Suite("Поворот за гіроскопом і стоянка")
struct TurnDetectorTests {
    @Test("Інтегрована кутова швидкість понад поріг дає поворот зі знаком напрямку")
    func detectsTurn() throws {
        var detector = TurnDetector()
        var detected: DetectedTurn?
        // Праворуч: -0,35 рад/с (≈20°/с) протягом 4 с.
        for step in 0...40 where detected == nil {
            detected = detector.add(YawSample(rate: -0.35, timestamp: Double(step) * 0.1), thresholdDegrees: 45)
        }
        let turn = try #require(detected)
        #expect(turn.degrees <= -45)
        #expect(turn.timestamp < 2.6)
    }

    @Test("Дрібні коливання не є поворотом")
    func ignoresWobble() {
        var detector = TurnDetector()
        for step in 0..<200 {
            let rate = step.isMultiple(of: 2) ? 0.2 : -0.2
            #expect(detector.add(YawSample(rate: rate, timestamp: Double(step) * 0.1), thresholdDegrees: 45) == nil)
        }
    }

    @Test("Поворот праворуч до повороту маршруту пропонує підтягнути точку, і кнопка її переставляє")
    func suggestsSnap() throws {
        var h = EngineHarness(along: 850)
        h.loseGPS()
        h.engine.handleTurn(degrees: -80, now: h.now)
        let suggestion = try #require(h.engine.turnSuggestion)
        #expect(abs(suggestion.distance - 150) < 0.5)
        h.engine.applyTurnSuggestion(now: h.now)
        #expect(abs(h.engine.along - 1000) < 0.5)
        #expect(h.engine.turnSuggestion == nil)
    }

    @Test("Поворот в інший бік, задалеко або в режимі GPS не пропонується")
    func noSuggestion() {
        var left = EngineHarness(along: 850)
        left.loseGPS()
        left.engine.handleTurn(degrees: 80, now: left.now)
        #expect(left.engine.turnSuggestion == nil)

        var far = EngineHarness(along: 500)
        far.loseGPS()
        far.engine.handleTurn(degrees: -80, now: far.now)
        #expect(far.engine.turnSuggestion == nil)

        var gps = EngineHarness(along: 850)
        gps.gps(along: 850)
        gps.engine.handleTurn(degrees: -80, now: gps.now)
        #expect(gps.engine.turnSuggestion == nil)
    }

    @Test("Пропозиція зникає, коли точка сама доїхала до повороту")
    func suggestionExpires() {
        var h = EngineHarness(along: 900)
        h.loseGPS()
        h.engine.handleTurn(degrees: -80, now: h.now)
        #expect(h.engine.turnSuggestion != nil)
        h.advance(11)
        #expect(h.engine.turnSuggestion == nil)
    }
}

@Suite("Датчики в сесії")
@MainActor
struct MotionSessionTests {
    @Test("Стоянка за датчиками зупиняє розрахункову точку")
    func stationaryStops() {
        let h = SessionHarness()
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.session.selectDeadReckoning()
        h.advance(10)
        let before = h.session.engine.along
        h.motion.send(.stationary)
        h.advance(20)
        #expect(h.session.engine.along == before)
        h.motion.send(.automotive)
        h.advance(10)
        #expect(abs(h.session.engine.along - before - 100) < 0.5)
    }

    @Test("«Рушити» через сесію: точка їде попри стоянку, у журналі є запис")
    func ignoreStationaryThroughSession() {
        let h = SessionHarness()
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.session.selectDeadReckoning()
        h.motion.send(.stationary)
        h.advance(10)
        #expect(h.session.engine.along == 0)
        h.session.ignoreStationary()
        h.motion.send(.stationary)
        h.advance(10)
        #expect(abs(h.session.engine.along - 100) < 0.5)
        #expect(h.log.messages.contains { $0.contains("водій рушив") })
    }

    @Test("Гіроскоп через сесію пропонує підтягнути до повороту")
    func gyroThroughSession() {
        let h = SessionHarness()
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.session.setPosition(along: 850)
        for step in 0...40 {
            h.motion.send(YawSample(rate: -0.4, timestamp: Double(step) * 0.1))
        }
        #expect(h.session.engine.turnSuggestion != nil)
        h.session.applyTurnSuggestion()
        #expect(abs(h.session.engine.along - 1000) < 0.5)
    }
}
