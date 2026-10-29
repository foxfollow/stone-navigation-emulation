import Foundation
import Testing
@testable import NavigationCore

@Suite("Точка з довгого тапу під час навігації")
@MainActor
struct MapPointTests {
    let destination = Place(name: "Фініш", coordinate: TestRoute.end)

    /// Навігація Г-подібним маршрутом у розрахунковому режимі, точка їде 10 м/с.
    func navigating() -> SessionHarness {
        let h = SessionHarness()
        h.session.begin(route: TestRoute.make(), destination: destination)
        h.session.selectDeadReckoning()
        h.advance(1)
        return h
    }

    @Test("«Я тут»: точка біля маршруту ставить позицію навпроти неї")
    func moveHereNearRoute() throws {
        let h = navigating()
        let point = TestRoute.point(along: 700, offset: 40)
        let projection = try #require(h.session.routeProjection(of: point))
        #expect(abs(projection.offset - 40) < 0.5)
        #expect(h.session.moveHere(point))
        #expect(abs(h.session.engine.along - 700) < 0.5)
        #expect(h.session.notice?.text == "Позицію переставлено")
        #expect(h.log.messages.contains { $0.hasPrefix("Корекція позиції (точка на карті)") })
    }

    @Test("«Я тут» не ставить позицію навпроти точки далі 100 м від маршруту: я не на ньому, треба перебудувати")
    func moveHereFarFromRoute() {
        let h = navigating()
        let before = h.session.engine.along
        #expect(!h.session.moveHere(TestRoute.point(along: 700, offset: 150)))
        #expect(h.session.engine.along == before)
    }

    @Test("«Маршрут звідси»: маршрут від точки до того самого пункту призначення, точка їде далі без паузи")
    func rebuildFromPoint() async throws {
        let h = navigating()
        let wrongTurn = Geo.destination(from: TestRoute.point(along: 500), bearing: 270, distance: 400)
        await h.session.rebuildRoute(from: Place(name: "Вибрана точка", coordinate: wrongTurn))
        let request = try #require(h.routes.requests.last)
        #expect(request.origin == wrongTurn)
        #expect(request.destination == destination.coordinate)
        #expect(h.session.destination == destination)
        #expect(h.session.engine.along == 0)
        #expect(!h.session.engine.reckoner.isPaused)
        #expect(h.session.notice?.text == "Маршрут перебудовано звідси, їдемо далі")
        h.advance(2)
        #expect(abs(h.session.engine.along - 20) < 0.01)
    }

    @Test("Точка стояла на паузі: після «Маршрут звідси» вона чекає на старті нового маршруту")
    func rebuildKeepsPause() async {
        let h = navigating()
        h.session.togglePause()
        await h.session.rebuildRoute(from: Place(name: "Вибрана точка", coordinate: TestRoute.point(along: 300, offset: 300)))
        #expect(h.session.engine.along == 0)
        #expect(h.session.engine.reckoner.isPaused)
        h.advance(5)
        #expect(h.session.engine.along == 0)
    }
}
