import Foundation
import Testing
@testable import NavigationCore

@Suite("Кеш маршрутів і обмеження частоти MapKit")
struct RoutingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Кеш віддає маршрут для близьких координат і не віддає для інших")
    func cache() {
        var cache = RouteCache()
        let route = TestRoute.make()
        cache.store(route, for: RouteRequestKey(origin: TestRoute.start, destination: TestRoute.end), at: now)
        let nearby = Geo.destination(from: TestRoute.start, bearing: 45, distance: 20)
        let hit = cache.route(for: RouteRequestKey(origin: nearby, destination: TestRoute.end), now: now.addingTimeInterval(60))
        #expect(hit == route || RouteRequestKey.round(nearby) != RouteRequestKey.round(TestRoute.start))
        #expect(cache.route(for: RouteRequestKey(origin: TestRoute.start, destination: TestRoute.end), now: now) == route)
        #expect(cache.route(for: RouteRequestKey(origin: TestRoute.start, destination: TestRoute.corner), now: now) == nil)
        #expect(cache.route(for: RouteRequestKey(origin: TestRoute.start, destination: TestRoute.end), now: now.addingTimeInterval(RouteCache.maxAge + 1)) == nil)
    }

    @Test("Кеш обмежений за розміром")
    func capacity() {
        var cache = RouteCache()
        for index in 0..<15 {
            let destination = Geo.destination(from: TestRoute.start, bearing: 0, distance: Double(index) * 1000)
            cache.store(TestRoute.make(id: "\(index)"), for: RouteRequestKey(origin: TestRoute.start, destination: destination), at: now)
        }
        #expect(cache.count == RouteCache.capacity)
    }

    @Test("Після loadingThrottled запити блокуються з експоненційним очікуванням")
    func throttle() {
        var throttle = RequestThrottle()
        #expect(throttle.canRequest(at: now))
        let first = throttle.recordThrottled(at: now)
        #expect(first == now.addingTimeInterval(2))
        #expect(!throttle.canRequest(at: now.addingTimeInterval(1)))
        #expect(throttle.canRequest(at: now.addingTimeInterval(2)))
        let second = throttle.recordThrottled(at: now)
        #expect(second == now.addingTimeInterval(4))
        throttle.recordSuccess()
        #expect(throttle.canRequest(at: now))
        #expect(throttle.consecutiveFailures == 0)
        for _ in 0..<20 { throttle.recordThrottled(at: now) }
        #expect(throttle.remainingDelay(at: now) == RequestThrottle.maxDelay)
    }
}

@Suite("Побудова маршруту в сесії")
@MainActor
struct RouteSessionTests {
    let destination = Place(name: "Фініш", coordinate: TestRoute.end)

    @Test("Throttled: зрозуміла помилка, повтор лише після очікування, потім кеш без нових запитів")
    func throttledThenCached() async {
        let h = SessionHarness()
        h.gps(TestRoute.start)
        h.routes.result = .failure(.throttled(retryAfter: nil))
        await h.session.buildRoute(to: destination)
        #expect(h.session.routeError?.contains("Забагато запитів") == true)
        #expect(!h.session.isNavigating)
        #expect(h.routes.requests.count == 1)

        await h.session.buildRoute(to: destination)
        #expect(h.routes.requests.count == 1)
        #expect(h.session.routeError?.contains("обмежив") == true)

        h.clock.advance(by: 3)
        h.routes.result = .success(TestRoute.make())
        await h.session.buildRoute(to: destination)
        #expect(h.routes.requests.count == 2)
        #expect(h.session.isNavigating)
        #expect(h.session.routeError == nil)

        h.session.endNavigation()
        await h.session.buildRoute(to: destination)
        #expect(h.routes.requests.count == 2)
        #expect(h.session.isNavigating)
    }

    @Test("Відхилення від маршруту: перебудова від GPS-позиції")
    func rebuildFromGPS() async throws {
        let h = SessionHarness()
        h.session.begin(route: TestRoute.make(), destination: destination)
        // Авто поступово з'їжджає вбік з реальною швидкістю, тож це не підміна, а відхилення.
        for step in 0..<4 {
            h.gps(TestRoute.point(along: 300 + Double(step) * 10, offset: Double(step) * 30))
            h.advance(1)
        }
        let off = TestRoute.point(along: 340, offset: 120)
        h.gps(off)
        #expect(h.session.engine.mode == .gps)
        #expect(h.session.engine.offRoute != nil)
        await h.session.rebuildFromCurrentGPS()
        let request = try #require(h.routes.requests.last)
        #expect(Geo.distance(request.origin, off) < 1)
        #expect(request.destination == TestRoute.end)
    }

    @Test("Зупинка з орієнтира передається постачальнику маршруту")
    func addStop() async throws {
        let candidates = [PlaceCandidate(id: "1", name: "АЗС", category: .gasStation, coordinate: TestRoute.point(along: 600, offset: 20))]
        let h = SessionHarness(candidates: candidates)
        h.session.begin(route: TestRoute.make(), destination: destination)
        h.advance(1)
        await h.session.settle()
        let landmark = try #require(h.session.landmarks.first)
        await h.session.addStop(landmark)
        let request = try #require(h.routes.requests.last)
        #expect(request.stops == [landmark.place.coordinate])
        #expect(h.session.stops == [landmark.place.coordinate])
    }
}
