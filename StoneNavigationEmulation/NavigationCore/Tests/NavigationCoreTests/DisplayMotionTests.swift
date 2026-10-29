import Foundation
import Testing
@testable import NavigationCore

@Suite("Плавний рух точки на екрані")
struct DisplayMotionTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    /// Моменти кадрів: 30 разів на секунду.
    func frames(seconds: Double, rate: Double = 30) -> [TimeInterval] {
        (0...Int(seconds * rate)).map { Double($0) / rate }
    }

    @Test("Рушій оновлює позицію раз на секунду, а точка на екрані їде рівно, без ривків і без відставання")
    func steadyMotion() {
        var smoother = PositionSmoother()
        var previous: Double?
        for t in frames(seconds: 5) {
            let tick = t.rounded(.down)
            let motion = RouteMotion(along: 10 * tick, time: start + tick, speed: 10, routeLength: 1000)
            let along = smoother.update(motion, now: start + t)
            #expect(abs(along - 10 * t) < 0.01)
            if let previous { #expect(abs((along - previous) - 10.0 / 30) < 0.01) }
            previous = along
        }
    }

    @Test("Поправка від GPS зникає плавно: точка не стрибає ні вперед, ні назад")
    func correctionIsSmooth() {
        var smoother = PositionSmoother()
        var previous: Double?
        var maxStep = 0.0
        for t in frames(seconds: 4) {
            let tick = t.rounded(.down)
            // З другої секунди GPS каже, що авто на 6 м попереду розрахунку.
            let correction = tick >= 2 ? 6.0 : 0
            let motion = RouteMotion(along: 10 * tick + correction, time: start + tick, speed: 10, routeLength: 1000)
            let along = smoother.update(motion, now: start + t)
            if let previous {
                #expect(along > previous)
                maxStep = max(maxStep, along - previous)
            }
            previous = along
        }
        // За кадр 0,33 м рівного ходу плюс частка поправки, а не всі 6 м одразу.
        #expect(maxStep < 1.5)
        #expect(abs((previous ?? 0) - 46) < 0.3)
    }

    @Test("Великий стрибок (новий маршрут, тап далеко по лінії) показується одразу")
    func bigJumpSnaps() {
        var smoother = PositionSmoother()
        _ = smoother.update(RouteMotion(along: 100, time: start, speed: 0, routeLength: 5000), now: start)
        let along = smoother.update(RouteMotion(along: 1500, time: start + 0.1, speed: 0, routeLength: 5000), now: start + 0.1)
        #expect(along == 1500)
    }

    @Test("Без нових даних точка забігає наперед не більше ніж на 1,5 с і не виїжджає за кінець маршруту")
    func predictionLimits() {
        var smoother = PositionSmoother()
        var along = 0.0
        for t in frames(seconds: 5) {
            along = smoother.update(RouteMotion(along: 0, time: start, speed: 10, routeLength: 1000), now: start + t)
        }
        #expect(along > 14.9 && along < 15.1)
        smoother.reset()
        along = smoother.update(RouteMotion(along: 995, time: start, speed: 10, routeLength: 1000), now: start + 1)
        #expect(along == 1000)
    }

    @Test("Точка, що стоїть, доходить до місця і далі не змінюється: карта не перемальовується щокадру")
    func settlesExactly() {
        var smoother = PositionSmoother()
        var heading = HeadingSmoother()
        _ = smoother.update(RouteMotion(along: 100, time: start, speed: 0, routeLength: 1000), now: start)
        _ = heading.update(10, now: start)
        var along = 0.0
        var angle = 0.0
        for t in frames(seconds: 4).dropFirst() {
            // Пауза: рушій поставив точку на 104 м, курс 30°.
            along = smoother.update(RouteMotion(along: 104, time: start, speed: 0, routeLength: 1000), now: start + t)
            angle = heading.update(30, now: start + t)
        }
        #expect(along == 104)
        #expect(angle == 30)
        #expect(smoother.update(RouteMotion(along: 104, time: start, speed: 0, routeLength: 1000), now: start + 4.1) == 104)
    }

    @Test("Курс на повороті маршруту повертається плавно і коротшим шляхом через північ")
    func headingTurnsSmoothly() {
        var smoother = HeadingSmoother()
        #expect(smoother.update(350, now: start) == 350)
        var previous = 350.0
        var maxStep = 0.0
        for t in frames(seconds: 3).dropFirst() {
            let heading = smoother.update(20, now: start + t)
            let step = Geo.normalizedAngle(heading - previous)
            #expect(step >= 0, "через північ, а не назад через південь")
            maxStep = max(maxStep, step)
            previous = heading
        }
        #expect(maxStep < 4)
        #expect(abs(Geo.normalizedAngle(previous - 20)) < 0.5)
    }

    @MainActor
    @Test("Пауза посеред секунди: точка стає там, де була в мить натискання, а «Далі» рушає з цієї миті")
    func pauseBetweenTicks() {
        let h = SessionHarness()
        // 2 км за 200 с: 10 м/с.
        h.session.begin(route: TestRoute.make(expectedTravelTime: 200), destination: nil)
        h.session.selectDeadReckoning()
        h.advance(1)
        h.advance(1)
        let before = h.session.engine.along
        h.clock.advance(by: 0.5)
        h.session.togglePause()
        #expect(abs(h.session.engine.along - (before + 5)) < 0.01)
        let paused = h.session.motion(at: h.clock.now)
        #expect(paused?.speed == 0)
        #expect(paused?.time == h.clock.now)
        h.advance(0.5)
        #expect(abs(h.session.engine.along - (before + 5)) < 0.01, "на паузі стоїть")

        h.clock.advance(by: 0.75)
        h.session.togglePause()
        h.advance(0.25)
        #expect(abs(h.session.engine.along - (before + 7.5)) < 0.01, "рушає з миті «Далі», а не з попереднього оновлення")

        // Нова швидкість теж діє лише з миті натискання.
        h.clock.advance(by: 0.5)
        h.session.speedUp()
        let speed = h.session.engine.speedInfo.speed
        #expect(speed > 10)
        h.advance(0.5)
        #expect(abs(h.session.engine.along - (before + 12.5 + speed * 0.5)) < 0.01)
    }

    @MainActor
    @Test("Для екрана: на GPS швидкість і час точки GPS, у розрахунковому режимі швидкість і час оновлення рушія")
    func motionForDisplay() {
        let h = SessionHarness()
        let route = TestRoute.make(expectedTravelTime: 200)
        h.session.begin(route: route, destination: nil)
        h.gps(TestRoute.point(along: 100, route: route), speed: 12)
        let fixTime = h.clock.now
        var motion = h.session.motion(at: fixTime)
        #expect(motion?.speed == 12)
        #expect(abs((motion?.along ?? 0) - 100) < 0.5)
        #expect(motion?.time == fixTime)

        // Оновлення без нової точки GPS позицію не зрушує: час лишається часом точки.
        h.advance(0.5)
        motion = h.session.motion(at: h.clock.now)
        #expect(motion?.time == fixTime)

        h.session.selectDeadReckoning()
        h.advance(1)
        motion = h.session.motion(at: h.clock.now)
        #expect(motion?.speed == 10)
        #expect(motion?.time == h.clock.now)
        h.session.togglePause()
        #expect(h.session.motion(at: h.clock.now)?.speed == 0)
    }
}
