import Foundation

public enum SpeedSource: String, Codable, Sendable {
    case manual
    case route
    case gps
    case standard

    public var title: String {
        switch self {
        case .manual: "вручну"
        case .route: "з маршруту"
        case .gps: "з GPS"
        case .standard: "стандартна"
        }
    }
}

/// Швидкість розрахункової позиції та її джерело, пауза і стоянка.
public struct DeadReckoner: Codable, Sendable, Equatable {
    /// Ручна швидкість, м/с. Діє, доки користувач не натисне «Скинути».
    public var manualSpeed: Double?
    public var isPaused = false
    /// Телефон фіксує стоянку (CMMotionActivity.stationary).
    public var isStationary = false
    /// Остання відома швидкість GPS, м/с.
    public var lastGPSSpeed: Double?

    /// Нижче цієї швидкості GPS не вважаємо її корисною для розрахунку (стоїмо або шум).
    static let minimumUsefulGPSSpeed = 1.0

    public init() {}

    /// Автоматична швидкість: маршрут → остання GPS → стандартна з Налаштувань.
    public func automaticSpeed(routeAverage: Double?, settings: NavigationSettings) -> (speed: Double, source: SpeedSource) {
        if let routeAverage, routeAverage > 0 { return (routeAverage, .route) }
        if let lastGPSSpeed, lastGPSSpeed >= Self.minimumUsefulGPSSpeed { return (lastGPSSpeed, .gps) }
        return (settings.defaultSpeed, .standard)
    }

    /// Поточна швидкість з урахуванням ручної.
    public func speed(routeAverage: Double?, settings: NavigationSettings) -> (speed: Double, source: SpeedSource) {
        if let manualSpeed { return (manualSpeed, .manual) }
        return automaticSpeed(routeAverage: routeAverage, settings: settings)
    }

    /// Швидкість, з якою точка рухається зараз: нуль на паузі або на стоянці.
    public func movingSpeed(routeAverage: Double?, settings: NavigationSettings) -> Double {
        guard !isPaused, !isStationary else { return 0 }
        return speed(routeAverage: routeAverage, settings: settings).speed
    }

    public mutating func increase(routeAverage: Double?, settings: NavigationSettings) {
        let current = speed(routeAverage: routeAverage, settings: settings).speed
        manualSpeed = min(current + settings.speedStep, settings.impossibleSpeed)
    }

    public mutating func decrease(routeAverage: Double?, settings: NavigationSettings) {
        let current = speed(routeAverage: routeAverage, settings: settings).speed
        manualSpeed = max(current - settings.speedStep, 0)
    }

    public mutating func resetManualSpeed() {
        manualSpeed = nil
    }
}
