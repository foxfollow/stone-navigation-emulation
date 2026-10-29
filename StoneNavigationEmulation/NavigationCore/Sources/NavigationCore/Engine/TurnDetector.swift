import Foundation

/// Поворот, зафіксований гіроскопом.
public struct DetectedTurn: Sendable, Equatable {
    /// Кут повороту, градуси. Додатний ліворуч (проти годинникової стрілки), від'ємний праворуч.
    public let degrees: Double
    public let timestamp: TimeInterval
}

/// Інтегрує кутову швидкість навколо вертикалі і повідомляє про поворот, коли кут перевищив поріг.
public struct TurnDetector: Sendable {
    /// Вікно інтегрування: поворот на перехресті займає кілька секунд.
    public var window: TimeInterval = 8
    private var samples: [YawSample] = []

    public init() {}

    public mutating func add(_ sample: YawSample, thresholdDegrees: Double) -> DetectedTurn? {
        samples.append(sample)
        samples.removeAll { sample.timestamp - $0.timestamp > window }
        guard samples.count > 1 else { return nil }
        var radians = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) {
            radians += a.rate * (b.timestamp - a.timestamp)
        }
        let degrees = radians * 180 / .pi
        guard abs(degrees) >= thresholdDegrees else { return nil }
        samples.removeAll()
        return DetectedTurn(degrees: degrees, timestamp: sample.timestamp)
    }

    public mutating func reset() {
        samples.removeAll()
    }
}
