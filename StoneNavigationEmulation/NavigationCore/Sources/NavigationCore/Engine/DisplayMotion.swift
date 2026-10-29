import Foundation

/// Що рушій знає про рух точки: позиція вздовж маршруту, коли її пораховано, і швидкість уздовж маршруту.
public struct RouteMotion: Sendable, Equatable {
    public var along: Double
    /// Коли рушій востаннє зрушив позицію (оновлення розрахункової точки або точка GPS).
    public var time: Date
    /// Швидкість уздовж маршруту, м/с: 0 на паузі, на стоянці і без швидкості GPS.
    public var speed: Double
    public var routeLength: Double

    public init(along: Double, time: Date, speed: Double, routeLength: Double) {
        self.along = along
        self.time = time
        self.speed = speed
        self.routeLength = routeLength
    }
}

/// Позиція для екрана. Рушій рахує її раз на `updateInterval` (стандартно 1 с), а екран малює 30–60 разів
/// на секунду. Між оновленнями точка їде далі з поточною швидкістю, а розбіжність із новим розрахунком
/// (точка GPS, «Вперед», зміна швидкості) зникає плавно, без ривків.
public struct PositionSmoother: Sendable {
    /// За стільки секунд розбіжність із розрахунком зменшується в e разів.
    public static let catchUpTime: TimeInterval = 0.3
    /// Довше за це без нових даних не передбачаємо: точка зупиняється і чекає.
    public static let maxPrediction: TimeInterval = 1.5
    /// Стрибок більший за це (новий маршрут, тап по лінії далеко) показуємо одразу.
    public static let snapDistance = 300.0
    /// Ближче за це точка вже на місці: далі значення не змінюється, і карта не перемальовується щокадру.
    public static let settleDistance = 0.01

    public private(set) var along: Double?
    private var lastFrame: Date?

    public init() {}

    public mutating func update(_ motion: RouteMotion, now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(motion.time))
        let speed = elapsed < Self.maxPrediction ? motion.speed : 0
        let predicted = clamp(motion.along + motion.speed * min(elapsed, Self.maxPrediction), motion.routeLength)
        defer { lastFrame = now }
        guard let current = along, let last = lastFrame, abs(predicted - current) < Self.snapDistance else {
            along = predicted
            return predicted
        }
        // Свій хід зі швидкістю, потім м'яко до розрахунку: на рівній швидкості відставання немає.
        let frame = min(max(0, now.timeIntervalSince(last)), 0.5)
        let moved = current + speed * frame
        var next = clamp(moved + (predicted - moved) * (1 - exp(-frame / Self.catchUpTime)), motion.routeLength)
        if abs(predicted - next) < Self.settleDistance { next = predicted }
        along = next
        return next
    }

    public mutating func reset() {
        along = nil
        lastFrame = nil
    }

    private func clamp(_ value: Double, _ length: Double) -> Double {
        min(max(0, value), max(0, length))
    }
}

/// Курс для камери і значка позиції. На вершинах ламаної маршруту курс змінюється стрибком,
/// а на екрані карта і стрілка повертаються плавно, коротшим шляхом через північ.
public struct HeadingSmoother: Sendable {
    /// За стільки секунд різниця з курсом зменшується в e разів.
    public static let turnTime: TimeInterval = 0.4
    /// Ближче за це, градуси, курс уже на місці.
    public static let settleAngle = 0.01

    public private(set) var heading: Double?
    private var lastFrame: Date?

    public init() {}

    public mutating func update(_ target: Double, now: Date) -> Double {
        defer { lastFrame = now }
        guard let current = heading, let last = lastFrame else {
            heading = Self.normalized(target)
            return heading ?? 0
        }
        let frame = min(max(0, now.timeIntervalSince(last)), 0.5)
        let delta = Geo.normalizedAngle(target - current)
        let rest = delta * exp(-frame / Self.turnTime)
        let next = Self.normalized(abs(rest) < Self.settleAngle ? target : current + delta - rest)
        heading = next
        return next
    }

    public mutating func reset() {
        heading = nil
        lastFrame = nil
    }

    /// Кут у діапазоні [0, 360).
    static func normalized(_ degrees: Double) -> Double {
        let angle = degrees.truncatingRemainder(dividingBy: 360)
        return angle < 0 ? angle + 360 : angle
    }
}
