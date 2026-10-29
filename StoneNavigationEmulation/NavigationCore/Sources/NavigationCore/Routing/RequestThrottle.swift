import Foundation

/// Експоненційне очікування після MKError.loadingThrottled: 2, 4, 8 … до 120 с.
public struct RequestThrottle: Codable, Sendable, Equatable {
    public static let baseDelay: TimeInterval = 2
    public static let maxDelay: TimeInterval = 120

    public private(set) var blockedUntil: Date?
    public private(set) var consecutiveFailures = 0

    public init() {}

    public func canRequest(at now: Date) -> Bool {
        guard let blockedUntil else { return true }
        return now >= blockedUntil
    }

    public func remainingDelay(at now: Date) -> TimeInterval {
        guard let blockedUntil else { return 0 }
        return max(0, blockedUntil.timeIntervalSince(now))
    }

    @discardableResult
    public mutating func recordThrottled(at now: Date, retryAfter: TimeInterval? = nil) -> Date {
        consecutiveFailures += 1
        let exponential = Self.baseDelay * pow(2, Double(consecutiveFailures - 1))
        let delay = min(Self.maxDelay, retryAfter ?? exponential)
        let until = now.addingTimeInterval(delay)
        blockedUntil = until
        return until
    }

    public mutating func recordSuccess() {
        consecutiveFailures = 0
        blockedUntil = nil
    }
}
