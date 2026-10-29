import Foundation

public enum SpoofKind: String, Codable, Sendable {
    /// Точка стрибнула далі за межу підміни з неможливою швидкістю.
    case jump
    /// Швидкість між точками більша, ніж авто може фізично проїхати.
    case impossibleSpeed
    /// Курс різко змінився там, де на маршруті немає повороту.
    case courseJump

    public var title: String {
        switch self {
        case .jump: "стрибок позиції"
        case .impossibleSpeed: "неможлива швидкість"
        case .courseJump: "різка зміна курсу без повороту"
        }
    }

    var modeReason: ModeReason {
        switch self {
        case .jump: .spoofJump
        case .impossibleSpeed: .spoofSpeed
        case .courseJump: .spoofCourse
        }
    }
}

/// Порівнює нову точку з попередньою доброю і вирішує, чи схоже це на підміну.
public enum SpoofDetector {
    /// Мінімальний інтервал між точками: щоб дві точки з однаковим часом не давали нескінченну швидкість.
    static let minimumInterval: TimeInterval = 0.5

    public static func check(previous: LocationFix, current: LocationFix, settings: NavigationSettings, route: Route?) -> SpoofKind? {
        let interval = current.timestamp.timeIntervalSince(previous.timestamp)
        let distance = Geo.distance(previous.coordinate, current.coordinate)
        // Похибки обох точок можуть «з'їсти» частину відстані, тому їх віднімаємо.
        let noise = max(0, previous.horizontalAccuracy) + max(0, current.horizontalAccuracy)
        let effectiveDistance = max(0, distance - noise)
        let impliedSpeed = effectiveDistance / max(interval, minimumInterval)
        if impliedSpeed > settings.impossibleSpeed {
            return effectiveDistance >= settings[.spoofDistance] ? .jump : .impossibleSpeed
        }

        guard let route,
              interval > 0, interval <= settings[.staleAge],
              previous.hasCourse, current.hasCourse,
              previous.speed >= settings.courseMinSpeed, current.speed >= settings.courseMinSpeed else { return nil }
        let courseChange = abs(Geo.normalizedAngle(current.course - previous.course))
        guard courseChange > settings[.courseJumpDegrees] else { return nil }
        guard let projection = route.polyline.project(current.coordinate) else { return nil }
        return routeTurns(near: projection.along, route: route, settings: settings) ? nil : .courseJump
    }

    /// Чи є на маршруті поворот біля дистанції: маневр або вигин лінії.
    static func routeTurns(near along: Double, route: Route, settings: NavigationSettings) -> Bool {
        let radius = settings[.turnProximity]
        if route.maneuvers.contains(where: { abs($0.along - along) <= radius }) { return true }
        let before = route.polyline.bearing(at: along - radius)
        let after = route.polyline.bearing(at: along + radius)
        return abs(Geo.normalizedAngle(after - before)) >= settings[.courseJumpDegrees]
    }
}
