import Foundation
import Testing
@testable import NavigationCore

@Suite("Повернення на GPS")
struct ReturnToGPSTests {
    /// Розрахунковий режим на дистанції 500 м, точка стоїть (пауза), щоб відстані були точними.
    func deadReckoningAt500(settings: NavigationSettings = .standard) -> EngineHarness {
        var h = EngineHarness(settings: settings, along: 500)
        h.loseGPS()
        h.engine.togglePause()
        _ = h.engine.drainEvents()
        return h
    }

    @Test("Точність краща за поріг протягом заданого часу повертає GPS")
    func returnsAfterDuration() {
        var h = deadReckoningAt500()
        for second in 0...4 {
            h.gps(along: 520, accuracy: 10)
            #expect(h.engine.mode == .deadReckoning, "секунда \(second)")
            h.advance(1)
        }
        h.gps(along: 520, accuracy: 10)
        #expect(h.engine.mode == .gps)
        #expect(h.engine.modeReason == .gpsRestored)
        #expect(abs(h.engine.along - 520) < 0.5)
        #expect(h.engine.drainEvents().contains(.modeChanged(from: .deadReckoning, to: .gps, reason: .gpsRestored)))
    }

    @Test("Точність між порогами (гірша за 30, краща за 100) не повертає GPS")
    func hysteresis() {
        var h = deadReckoningAt500()
        for _ in 0..<20 {
            h.gps(along: 500, accuracy: 50)
            h.advance(1)
        }
        #expect(h.engine.mode == .deadReckoning)
    }

    @Test("Одна погана точка скидає відлік часу")
    func streakResets() {
        var h = deadReckoningAt500()
        for _ in 0..<4 { h.gps(along: 500, accuracy: 10); h.advance(1) }
        h.gps(along: 500, accuracy: 60)
        h.advance(1)
        for _ in 0..<5 { h.gps(along: 500, accuracy: 10); h.advance(1) }
        #expect(h.engine.mode == .deadReckoning)
        h.gps(along: 500, accuracy: 10)
        #expect(h.engine.mode == .gps)
    }

    @Test("Пороги повернення беруться з Налаштувань")
    func settingsDriveReturn() {
        var settings = NavigationSettings()
        settings[.returnAccuracy] = 60
        settings[.returnDuration] = 2
        var h = deadReckoningAt500(settings: settings)
        h.gps(along: 500, accuracy: 50); h.advance(1)
        h.gps(along: 500, accuracy: 50); h.advance(1)
        h.gps(along: 500, accuracy: 50)
        #expect(h.engine.mode == .gps)
    }

    @Test("GPS далі за межу підміни: запит, а режим лишається розрахунковим")
    func farGPSShowsPrompt() {
        var h = deadReckoningAt500()
        for _ in 0...5 {
            h.gps(along: 1500, accuracy: 5)
            h.advance(1)
        }
        #expect(h.engine.mode == .deadReckoning)
        let prompt = h.engine.spoofPrompt
        #expect(prompt != nil)
        #expect((prompt?.distance ?? 0) > 500)
        #expect(h.engine.drainEvents().contains { if case .returnPrompt = $0 { true } else { false } })
    }

    @Test("«Лишити розрахункову» ховає запит на час із Налаштувань")
    func keepSuppressesPrompt() {
        var h = deadReckoningAt500()
        for _ in 0...5 { h.gps(along: 1500); h.advance(1) }
        #expect(h.engine.spoofPrompt != nil)
        h.engine.keepDeadReckoning(now: h.now)
        #expect(h.engine.spoofPrompt == nil)
        for _ in 0..<50 { h.gps(along: 1500); h.advance(1) }
        #expect(h.engine.spoofPrompt == nil)
        #expect(h.engine.mode == .deadReckoning)
        for _ in 0..<15 { h.gps(along: 1500); h.advance(1) }
        #expect(h.engine.spoofPrompt != nil)
    }

    @Test("«Перейти на GPS» переходить плавно")
    func acceptMovesSmoothly() {
        var h = deadReckoningAt500()
        for _ in 0...5 { h.gps(along: 1500); h.advance(1) }
        h.engine.acceptSpoofPrompt(now: h.now)
        #expect(h.engine.mode == .gps)
        #expect(h.engine.modeReason == .userAcceptedGPS)
        #expect(abs(h.engine.along - 1500) < 0.5)
        // Відображувана позиція стартує зі старої і за 2 с доходить до нової.
        #expect(abs(h.engine.displayAlong(at: h.now) - 500) < 0.5)
        let middle = h.engine.displayAlong(at: h.now.addingTimeInterval(1))
        #expect(middle > 600 && middle < 1400)
        #expect(abs(h.engine.displayAlong(at: h.now.addingTimeInterval(2)) - 1500) < 0.5)
        // Наступна точка поруч із новою позицією не вважається підміною.
        h.advance(1)
        h.gps(along: 1510)
        #expect(h.engine.mode == .gps)
    }

    @Test("Автоматичне повернення теж плавне")
    func automaticReturnIsSmooth() {
        var h = deadReckoningAt500()
        for _ in 0...5 { h.gps(along: 800); h.advance(1) }
        #expect(h.engine.mode == .gps)
        #expect(h.engine.displayAlong(at: h.now) < 800)
        h.advance(2)
        #expect(abs(h.engine.displayAlong(at: h.now) - 800) < 0.5)
    }

    @Test("Межа підміни з Налаштувань вирішує: повернення чи запит")
    func spoofDistanceFromSettings() {
        var settings = NavigationSettings()
        settings[.spoofDistance] = 1500
        var h = deadReckoningAt500(settings: settings)
        for _ in 0...5 { h.gps(along: 1500); h.advance(1) }
        #expect(h.engine.mode == .gps)
        #expect(h.engine.spoofPrompt == nil)
    }
}
