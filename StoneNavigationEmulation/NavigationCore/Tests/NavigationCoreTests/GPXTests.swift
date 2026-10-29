import Foundation
import Testing
@testable import NavigationCore

@Suite("GPX і програвання")
struct GPXTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Синтезований трек записується в GPX і читається назад")
    func roundTrip() throws {
        let track = GPXTrack.synthesize(along: TestRoute.make().polyline, speed: 10, interval: 1, start: start, name: "Тест")
        #expect(track.points.count == 201)
        let parsed = try GPXTrack.parse(Data(track.xml().utf8))
        #expect(parsed.name == "Тест")
        #expect(parsed.points.count == track.points.count)
        for (a, b) in zip(parsed.points, track.points) {
            #expect(Geo.distance(a.coordinate, b.coordinate) < 0.05)
            #expect(a.time == b.time)
        }
    }

    @Test("Неправильний GPX дає помилку")
    func invalid() {
        #expect(throws: GPXError.self) { try GPXTrack.parse(Data("<gpx><trk>".utf8)) }
        #expect(throws: GPXError.empty) { try GPXTrack.parse(Data(#"<gpx version="1.1"></gpx>"#.utf8)) }
    }

    @Test("Розклад програвання: зникнення GPS і стрибок позиції")
    func plan() throws {
        let track = GPXTrack.synthesize(along: TestRoute.make().polyline, speed: 10, interval: 1, start: start)
        let options = ReplayOptions(lossStart: 20, lossDuration: 30, jumpStart: 80, jumpDuration: 10, jumpDistance: 1500)
        let plan = ReplayPlanner.plan(track: track, options: options, start: start)

        let inLoss = plan.filter { (20..<50).contains($0.offset) }
        #expect(inLoss.count == 1)
        #expect(inLoss.first?.event == .error(.locationUnknown))

        let jumped = plan.filter { (80..<90).contains($0.offset) }
        #expect(jumped.count == 10)
        for item in jumped {
            guard case .fix(let fix) = item.event else { Issue.record("очікувалась точка"); continue }
            let original = track.points[Int(item.offset)].coordinate
            #expect(abs(Geo.distance(fix.coordinate, original) - 1500) < 1)
        }
        guard case .fix(let first) = plan.first?.event else { Issue.record("перша подія не точка"); return }
        #expect(first.timestamp == start)
        #expect(first.horizontalAccuracy == 5)
    }

    @Test("Програвання через рушій: GPS → розрахункова при зникненні → GPS, і так само при стрибку")
    func replayThroughEngine() {
        let route = TestRoute.make()
        let track = GPXTrack.synthesize(along: route.polyline, speed: 12, interval: 1, start: start)
        let options = ReplayOptions(lossStart: 20, lossDuration: 30, jumpStart: 100, jumpDuration: 10, jumpDistance: 1500)
        let plan = ReplayPlanner.plan(track: track, options: options, start: start)

        var engine = NavigationEngine(now: start)
        engine.setRoute(route, now: start)
        var modes: [(TimeInterval, NavigationMode, ModeReason)] = []
        var offset = 0.0
        var index = 0
        while offset <= 160 {
            let now = start.addingTimeInterval(offset)
            while index < plan.count, plan[index].offset <= offset {
                engine.handle(plan[index].event, now: now)
                index += 1
            }
            engine.tick(now: now)
            for case let .modeChanged(_, to, reason) in engine.drainEvents() {
                modes.append((offset, to, reason))
            }
            offset += 0.5
        }
        let transitions = modes.map { "\($0.1.rawValue):\($0.2.rawValue)" }
        #expect(transitions == [
            "deadReckoning:locationError",
            "gps:gpsRestored",
            "deadReckoning:spoofJump",
            "gps:gpsRestored",
        ])
        #expect(modes[0].0 == 20)
        // Після кінця зникнення (50 с) потрібно 5 с доброго сигналу.
        #expect(modes[1].0 == 55)
        #expect(modes[2].0 == 100)
        #expect(modes[3].0 >= 110)
    }
}
