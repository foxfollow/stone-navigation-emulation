import Foundation
import NavigationCore

/// Відтворювані сценарії для UI-тестів і скріншотів: розклад подій фейкової геолокації.
enum Scenarios {
    struct Setup {
        let plan: [ScheduledLocationEvent]
        let opensSettings: Bool
    }

    /// Звідки в треку починається сценарій: трохи від старту, щоб попереду був поворот.
    static let startOffset: TimeInterval = 40

    /// Сценарій `turn` починається за стільки метрів маршруту: попереду поворот на Братиславську з орієнтиром біля нього.
    static let turnScenarioAlong = 9700.0

    static func setup(for name: ScenarioName, track: GPXTrack, route: Route, start: Date) -> Setup {
        let base = ReplayPlanner.plan(track: track, options: ReplayOptions(), start: start)
        switch name {
        case .turn:
            let offset = base.first { item in
                guard case .fix(let fix) = item.event else { return false }
                return (route.polyline.project(fix.coordinate)?.along ?? 0) >= turnScenarioAlong
            }?.offset ?? startOffset
            return Setup(plan: shifted(base, from: offset), opensSettings: false)
        case .gps:
            return Setup(plan: shifted(base, from: startOffset), opensSettings: false)
        case .poi:
            return Setup(plan: shifted(base, from: startOffset), opensSettings: false)
        case .lost:
            // 4 с доброго сигналу, потім помилка CLLocationManager і тиша.
            var plan = Array(shifted(base, from: startOffset).prefix { $0.offset < 4 })
            plan.append(ScheduledLocationEvent(offset: 4, event: .error(.locationUnknown)))
            return Setup(plan: plan, opensSettings: false)
        case .spoof:
            // 5 с доброго сигналу, далі «ідеальна» точка за 1,5 км на схід (підміна).
            let options = ReplayOptions(jumpStart: startOffset + 5, jumpDuration: 3600, jumpDistance: 1500)
            let plan = ReplayPlanner.plan(track: track, options: options, start: start)
            return Setup(plan: shifted(plan, from: startOffset), opensSettings: false)
        case .settings:
            // Точність 80 м: GPS при стандартному порозі 100 м, розрахунок при порозі 50 м.
            let plan = ReplayPlanner.plan(track: track, options: ReplayOptions(accuracy: 80), start: start)
            return Setup(plan: shifted(plan, from: startOffset), opensSettings: true)
        }
    }

    /// Вигадане місце з довгою назвою за стільки метрів попереду від старту сценарію, ліворуч від дороги.
    static let longNameAhead = 260.0
    static let longNameID = "scenario.longName"

    /// Для сценаріїв `poi` і `lost` до записаних POI додається місце з довгою назвою: на ньому видно,
    /// як назва скорочується на карті до трьох слів і розгортається тапом. У записаному маршруті такої немає поруч зі стартом.
    static func extraLandmarks(for name: ScenarioName, route: Route, plan: [ScheduledLocationEvent]) -> [PlaceCandidate] {
        guard name == .poi || name == .lost else { return [] }
        let start = plan.lazy.compactMap { item -> Coordinate? in
            if case .fix(let fix) = item.event { fix.coordinate } else { nil }
        }.first
        let along = (start.flatMap { route.polyline.project($0)?.along } ?? 0) + longNameAhead
        let road = route.polyline.coordinate(at: along)
        let coordinate = Geo.destination(from: road, bearing: route.polyline.bearing(at: along) - 90, distance: 25)
        return [PlaceCandidate(
            id: longNameID,
            name: "Товари для художників та творчості \"Майстриня\"",
            category: .store,
            coordinate: coordinate,
            countryCode: "UA"
        )]
    }

    /// Відрізати початок і зсунути розклад так, щоб він починався з нуля.
    private static func shifted(_ plan: [ScheduledLocationEvent], from offset: TimeInterval) -> [ScheduledLocationEvent] {
        plan.filter { $0.offset >= offset }.map { item in
            var event = item.event
            if case .fix(var fix) = event {
                fix.timestamp = fix.timestamp.addingTimeInterval(-offset)
                event = .fix(fix)
            }
            return ScheduledLocationEvent(offset: item.offset - offset, event: event)
        }
    }
}

/// Датчики руху для сценаріїв (`-motion stationary`): одразу після старту повідомляють заданий стан.
@MainActor
final class FixedMotionSource: MotionSource {
    var onActivity: (@MainActor (MotionActivity) -> Void)?
    var onYawRate: (@MainActor (YawSample) -> Void)?
    private let activity: MotionActivity

    init(activity: MotionActivity) {
        self.activity = activity
    }

    func start() { onActivity?(activity) }
    func stop() {}
}
