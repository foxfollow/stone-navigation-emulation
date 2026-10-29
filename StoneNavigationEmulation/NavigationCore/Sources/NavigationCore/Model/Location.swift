import Foundation

/// Точка від джерела геолокації (аналог CLLocation).
public struct LocationFix: Codable, Sendable, Equatable {
    public var coordinate: Coordinate
    /// Горизонтальна похибка, метри. Від'ємна означає, що точка недійсна.
    public var horizontalAccuracy: Double
    /// Швидкість, м/с. Від'ємна означає, що невідома.
    public var speed: Double
    /// Курс, градуси від півночі. Від'ємний означає, що невідомий.
    public var course: Double
    public var timestamp: Date

    public init(coordinate: Coordinate, horizontalAccuracy: Double, speed: Double = -1, course: Double = -1, timestamp: Date) {
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.course = course
        self.timestamp = timestamp
    }

    public var hasValidAccuracy: Bool { horizontalAccuracy >= 0 }
    public var hasCourse: Bool { course >= 0 }
}

public enum LocationErrorKind: String, Codable, Sendable {
    case locationUnknown
    case denied
    case network
    case other

    public var title: String {
        switch self {
        case .locationUnknown: "позиція невідома"
        case .denied: "доступ заборонено"
        case .network: "помилка мережі"
        case .other: "інша помилка"
        }
    }
}

public enum LocationEvent: Sendable, Equatable {
    case fix(LocationFix)
    case error(LocationErrorKind)
}

/// Стан руху за CMMotionActivityManager.
public enum MotionActivity: String, Codable, Sendable {
    case stationary
    case automotive
    case walking
    case unknown

    public var title: String {
        switch self {
        case .stationary: "стоянка"
        case .automotive: "їзда"
        case .walking: "пішки"
        case .unknown: "невідомо"
        }
    }
}

/// Кутова швидкість навколо вертикалі: рад/с, додатна проти годинникової стрілки (поворот ліворуч).
public struct YawSample: Sendable, Equatable {
    public var rate: Double
    public var timestamp: TimeInterval

    public init(rate: Double, timestamp: TimeInterval) {
        self.rate = rate
        self.timestamp = timestamp
    }
}
