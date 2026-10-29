import Foundation
import Testing
@testable import NavigationCore

@Suite("Сесія навігації з фейковими портами")
@MainActor
struct SessionTests {
    @Test("Розрахункова позиція в сесії рухається за фейковим годинником")
    func deadReckoningWithFakeClock() {
        let h = SessionHarness()
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.gps(TestRoute.start)
        h.advance(1)
        h.advance(1)
        h.advance(1)
        h.advance(1)
        #expect(h.session.engine.mode == .deadReckoning)
        let start = h.session.engine.along
        h.advance(10)
        #expect(abs(h.session.engine.along - start - 100) < 0.01)
        let timer = h.session.engine.timeWithoutGPS(at: h.session.now) ?? 0
        #expect(timer == 14)
        #expect(h.session.estimatedArrival != nil)
    }

    @Test("Стан і маршрут переживають перезапуск")
    func persistence() throws {
        let store = InMemorySessionStore()
        let first = SessionHarness(store: store)
        first.session.begin(route: TestRoute.make(), destination: Place(name: "Фініш", coordinate: TestRoute.end))
        first.session.selectDeadReckoning()
        first.session.speedUp()
        first.advance(20)
        first.session.persist()
        let saved = try #require(store.snapshot)
        #expect(saved.isNavigating)

        // Новий запуск із тим самим сховищем.
        let second = SessionHarness(store: store)
        #expect(second.session.isNavigating)
        #expect(second.session.engine.route == TestRoute.make())
        #expect(abs(second.session.engine.along - saved.along) < 0.01)
        #expect(second.session.destination?.name == "Фініш")
        #expect(second.session.engine.reckoner.manualSpeed != nil)
        #expect(second.log.messages.contains { $0.hasPrefix("Відновлено навігацію") })
    }

    @Test("Зміна налаштувань у сесії одразу змінює поведінку")
    func applySettings() {
        let h = SessionHarness()
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.gps(TestRoute.point(along: 0), accuracy: 80)
        #expect(h.session.engine.mode == .gps)
        var strict = NavigationSettings()
        strict[.enterAccuracy] = 50
        h.session.apply(settings: strict)
        h.advance(1)
        h.gps(TestRoute.point(along: 10), accuracy: 80)
        #expect(h.session.engine.mode == .deadReckoning)
        #expect(h.session.engine.modeReason == .poorAccuracy)
    }

    @Test("Запит про підміну: «Лишити розрахункову» і «Перейти на GPS»")
    func spoofPromptFlow() {
        let h = SessionHarness()
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.gps(TestRoute.point(along: 100))
        h.advance(1)
        h.gps(TestRoute.point(along: 1600))
        #expect(h.session.engine.modeReason == .spoofJump)
        for step in 0...5 {
            h.gps(TestRoute.point(along: 1600 + Double(step) * 10))
            h.advance(1)
        }
        #expect(h.session.engine.spoofPrompt != nil)
        h.session.keepDeadReckoning()
        #expect(h.session.engine.spoofPrompt == nil)
        #expect(h.session.engine.mode == .deadReckoning)
        #expect(h.log.messages.contains("Користувач лишив розрахункову позицію"))
    }

    @Test("Заміна джерела геолокації для режиму тестування")
    func replaceSource() {
        let h = SessionHarness()
        let replacement = FakeLocationSource()
        h.session.replaceLocationSource(replacement)
        #expect(!h.location.isRunning)
        #expect(replacement.isRunning)
        replacement.send(.fix(.good(TestRoute.start, at: h.clock.now)))
        #expect(h.session.engine.lastRawFix != nil)
    }
}
