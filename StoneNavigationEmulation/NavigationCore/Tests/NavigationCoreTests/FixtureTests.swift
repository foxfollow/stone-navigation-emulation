import Foundation
import Testing
@testable import NavigationCore

@Suite("Записані фікстури MapKit")
struct FixtureTests {
    @Test("Записаний маршрут: polyline, кроки, маневри і середня швидкість")
    func recordedRoute() throws {
        let route = try Fixtures.route()
        #expect(route.coordinates.count > 20)
        #expect(route.steps.count > 3)
        #expect(route.maneuvers.count >= route.steps.count - 2)
        #expect(abs(route.polyline.length - route.distance) / route.distance < 0.05)
        let average = try #require(route.averageSpeed)
        #expect((2...30).contains(average))
        #expect(route.maneuvers.map(\.along) == route.maneuvers.map(\.along).sorted())
        #expect(route.maneuvers.contains { $0.isTurn })
    }

    @Test("Записаний GPX-трек іде вздовж записаного маршруту")
    func recordedTrack() throws {
        let route = try Fixtures.route()
        let track = try Fixtures.track()
        #expect(track.points.count > 100)
        let times = track.points.compactMap(\.time)
        #expect(times.count == track.points.count)
        #expect(times == times.sorted())
        for point in track.points {
            #expect((route.polyline.project(point.coordinate)?.offset ?? .infinity) < 5)
        }
    }

    @Test("Повний прогін GPX із втратою GPS: точка продовжує рух і повертається на GPS без запиту")
    func replayRecordedTrack() throws {
        let route = try Fixtures.route()
        let track = try Fixtures.track()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = ReplayPlanner.plan(track: track, options: ReplayOptions(lossStart: 60, lossDuration: 40), start: start)
        var engine = NavigationEngine(now: start)
        engine.setRoute(route, now: start)
        var index = 0
        var alongAtLoss: Double?
        var alongBeforeReturn: Double?
        var reasons: [ModeReason] = []
        for step in 0...240 {
            let now = start.addingTimeInterval(Double(step) * 0.5)
            while index < plan.count, plan[index].offset <= Double(step) * 0.5 {
                engine.handle(plan[index].event, now: now)
                index += 1
            }
            engine.tick(now: now)
            for case let .modeChanged(_, _, reason) in engine.drainEvents() { reasons.append(reason) }
            if engine.mode == .deadReckoning, alongAtLoss == nil { alongAtLoss = engine.along }
            if engine.mode == .deadReckoning { alongBeforeReturn = engine.along }
        }
        #expect(reasons == [.locationError, .gpsRestored])
        let lost = try #require(alongAtLoss)
        let last = try #require(alongBeforeReturn)
        #expect(last > lost + 100)
        #expect(engine.spoofPrompt == nil)
    }
}
