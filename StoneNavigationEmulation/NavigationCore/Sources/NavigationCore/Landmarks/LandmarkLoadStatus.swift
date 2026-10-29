import Foundation

/// Як ідуть запити орієнтирів за поїздку: видно на екрані «Орієнтири», щоб переконатися, що вони справді вантажаться.
public struct LandmarkLoadStatus: Sendable, Equatable {
    /// Успішні запити.
    public var requests = 0
    public var failures = 0
    /// Скільки місць прийшло в останній відповіді.
    public var lastFound = 0
    public var lastSuccessAt: Date?
    /// Ділянка, яку запитуємо зараз.
    public var loading: LandmarkArea?
    public var lastError: String?
    /// Коли автоматичний повтор після помилки чи обмеження MapKit.
    public var retryAt: Date?
    /// Скільки метрів попереду завантажено суцільно.
    public var coverageAhead: Double = 0

    public init() {}

    public var isLoading: Bool { loading != nil }
}
