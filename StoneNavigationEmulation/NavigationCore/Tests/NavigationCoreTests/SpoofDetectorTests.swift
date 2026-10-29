import Foundation
import Testing
@testable import NavigationCore

@Suite("Детектор підміни GPS")
struct SpoofDetectorTests {
    let route = TestRoute.make()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func fix(_ along: Double, offset: Double = 0, at seconds: TimeInterval, accuracy: Double = 5, speed: Double = 14, course: Double = -1) -> LocationFix {
        LocationFix.good(TestRoute.point(along: along, offset: offset, route: route), at: t0.addingTimeInterval(seconds), accuracy: accuracy, speed: speed, course: course)
    }

    @Test("Стрибок на 1,5 км за секунду це підміна типу «стрибок»")
    func jump() {
        let kind = SpoofDetector.check(previous: fix(100, at: 0), current: fix(1600, at: 1), settings: .standard, route: route)
        #expect(kind == .jump)
    }

    @Test("90 м за секунду (≈300 км/год) це неможлива швидкість")
    func impossibleSpeed() {
        let kind = SpoofDetector.check(previous: fix(100, at: 0), current: fix(190, at: 1), settings: .standard, route: route)
        #expect(kind == .impossibleSpeed)
    }

    @Test("Звичайна їзда 50 км/год не підміна")
    func normalDriving() {
        #expect(SpoofDetector.check(previous: fix(100, at: 0), current: fix(114, at: 1), settings: .standard, route: route) == nil)
    }

    @Test("Великий зсув за довгий час (72 км/год) не підміна")
    func slowOverLongGap() {
        #expect(SpoofDetector.check(previous: fix(0, at: 0), current: fix(1500, at: 75), settings: .standard, route: route) == nil)
    }

    @Test("Похибки точок віднімаються, щоб шум не давав хибних тривог")
    func noiseTolerance() {
        let noisy = SpoofDetector.check(previous: fix(100, at: 0, accuracy: 30), current: fix(170, at: 1, accuracy: 30), settings: .standard, route: route)
        #expect(noisy == nil)
    }

    @Test("Поріг неможливої швидкості береться з Налаштувань")
    func thresholdFromSettings() {
        // 60 м/с ≈ 216 км/год після віднімання похибок.
        let previous = fix(100, at: 0, accuracy: 0)
        let current = fix(160, at: 1, accuracy: 0)
        #expect(SpoofDetector.check(previous: previous, current: current, settings: .standard, route: route) == .impossibleSpeed)
        var relaxed = NavigationSettings()
        relaxed[.impossibleSpeedKmh] = 250
        #expect(SpoofDetector.check(previous: previous, current: current, settings: relaxed, route: route) == nil)
    }

    @Test("Різка зміна курсу на прямій ділянці це підміна")
    func courseJumpOnStraight() {
        let kind = SpoofDetector.check(previous: fix(400, at: 0, course: 0), current: fix(414, at: 1, course: 95), settings: .standard, route: route)
        #expect(kind == .courseJump)
    }

    @Test("Різка зміна курсу біля повороту маршруту нормальна")
    func courseChangeAtTurn() {
        let kind = SpoofDetector.check(previous: fix(990, at: 0, course: 0), current: fix(1004, at: 1, course: 90), settings: .standard, route: route)
        #expect(kind == nil)
    }

    @Test("На малій швидкості курс не перевіряється")
    func courseIgnoredWhenSlow() {
        let kind = SpoofDetector.check(previous: fix(400, at: 0, speed: 2, course: 0), current: fix(402, at: 1, speed: 2, course: 120), settings: .standard, route: route)
        #expect(kind == nil)
    }

    @Test("Рушій у режимі GPS переходить на розрахункову при стрибку і не приймає підмінену точку")
    func engineReactsToJump() {
        var h = EngineHarness()
        h.gps(along: 200)
        h.advance(1)
        h.gps(along: 1700)
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.modeReason == .spoofJump)
        #expect(abs(h.engine.along - 210) < 0.5)
        let events = h.engine.drainEvents()
        #expect(events.contains { if case .spoofSuspected(.jump, _) = $0 { true } else { false } })
    }

    @Test("Рушій реагує на неможливу швидкість")
    func engineReactsToImpossibleSpeed() {
        var h = EngineHarness()
        h.gps(along: 200)
        h.advance(1)
        h.gps(along: 300)
        #expect(h.engine.mode == .deadReckoning)
        #expect(h.engine.modeReason == .spoofSpeed)
    }
}
