import Foundation

/// Програє розклад подій геолокації в реальному часі: сценарії UI-тестів і режим тестування з GPX.
/// Часові мітки точок зсуваються на момент `start()`, тож точки завжди «свіжі».
@MainActor
public final class ScriptedLocationSource: LocationSource {
    public var onEvent: (@MainActor (LocationEvent) -> Void)?
    public let plan: [ScheduledLocationEvent]
    public private(set) var emittedCount = 0
    public private(set) var isRunning = false

    private let planStart: Date
    private var task: Task<Void, Never>?

    public init(plan: [ScheduledLocationEvent], planStart: Date) {
        self.plan = plan
        self.planStart = planStart
    }

    public func start() {
        guard task == nil else { return }
        isRunning = true
        let startedAt = Date()
        let shift = startedAt.timeIntervalSince(planStart)
        let plan = self.plan
        task = Task { [weak self] in
            for item in plan {
                let wait = startedAt.addingTimeInterval(item.offset).timeIntervalSinceNow
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                guard !Task.isCancelled, let self else { return }
                self.emit(Self.shifted(item.event, by: shift))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func emit(_ event: LocationEvent) {
        emittedCount += 1
        onEvent?(event)
    }

    private static func shifted(_ event: LocationEvent, by shift: TimeInterval) -> LocationEvent {
        guard case .fix(var fix) = event else { return event }
        fix.timestamp = fix.timestamp.addingTimeInterval(shift)
        return .fix(fix)
    }
}
