import Foundation

/// Параметри програвання GPX у режимі тестування.
public struct ReplayOptions: Codable, Sendable, Equatable {
    /// Коли GPS зникає (секунди від старту), nil означає, що не зникає.
    public var lossStart: TimeInterval?
    public var lossDuration: TimeInterval
    /// Коли позиція стрибає (підміна), nil означає, що не стрибає.
    public var jumpStart: TimeInterval?
    public var jumpDuration: TimeInterval
    public var jumpDistance: Double
    public var jumpBearing: Double
    public var accuracy: Double

    public init(
        lossStart: TimeInterval? = nil,
        lossDuration: TimeInterval = 30,
        jumpStart: TimeInterval? = nil,
        jumpDuration: TimeInterval = 15,
        jumpDistance: Double = 1500,
        jumpBearing: Double = 90,
        accuracy: Double = 5
    ) {
        self.lossStart = lossStart
        self.lossDuration = lossDuration
        self.jumpStart = jumpStart
        self.jumpDuration = jumpDuration
        self.jumpDistance = jumpDistance
        self.jumpBearing = jumpBearing
        self.accuracy = accuracy
    }
}

public struct ScheduledLocationEvent: Sendable, Equatable {
    /// Секунди від початку програвання.
    public var offset: TimeInterval
    public var event: LocationEvent

    public init(offset: TimeInterval, event: LocationEvent) {
        self.offset = offset
        self.event = event
    }
}

/// Перетворює GPX-трек на розклад подій геолокації з імітацією зникнення GPS і стрибка позиції.
public enum ReplayPlanner {
    public static func plan(track: GPXTrack, options: ReplayOptions, start: Date) -> [ScheduledLocationEvent] {
        let points = track.points
        guard let firstTime = points.first?.time else {
            return plan(points: points, offsets: points.indices.map(Double.init), options: options, start: start)
        }
        let offsets = points.enumerated().map { index, point in
            point.time.map { $0.timeIntervalSince(firstTime) } ?? Double(index)
        }
        return plan(points: points, offsets: offsets, options: options, start: start)
    }

    private static func plan(points: [GPXPoint], offsets: [TimeInterval], options: ReplayOptions, start: Date) -> [ScheduledLocationEvent] {
        var result: [ScheduledLocationEvent] = []
        var lossReported = false
        for (index, point) in points.enumerated() {
            let offset = offsets[index]
            if let lossStart = options.lossStart, offset >= lossStart, offset < lossStart + options.lossDuration {
                if !lossReported {
                    result.append(ScheduledLocationEvent(offset: offset, event: .error(.locationUnknown)))
                    lossReported = true
                }
                continue
            }
            var coordinate = point.coordinate
            if let jumpStart = options.jumpStart, offset >= jumpStart, offset < jumpStart + options.jumpDuration {
                coordinate = Geo.destination(from: coordinate, bearing: options.jumpBearing, distance: options.jumpDistance)
            }
            let fix = LocationFix(
                coordinate: coordinate,
                horizontalAccuracy: options.accuracy,
                speed: point.speed ?? derivedSpeed(points: points, offsets: offsets, index: index),
                course: point.course ?? derivedCourse(points: points, index: index),
                timestamp: start.addingTimeInterval(offset)
            )
            result.append(ScheduledLocationEvent(offset: offset, event: .fix(fix)))
        }
        return result
    }

    private static func derivedSpeed(points: [GPXPoint], offsets: [TimeInterval], index: Int) -> Double {
        let other = index + 1 < points.count ? index + 1 : index - 1
        guard other >= 0, other != index else { return -1 }
        let dt = abs(offsets[other] - offsets[index])
        guard dt > 0 else { return -1 }
        return Geo.distance(points[index].coordinate, points[other].coordinate) / dt
    }

    private static func derivedCourse(points: [GPXPoint], index: Int) -> Double {
        if index + 1 < points.count {
            return Geo.bearing(from: points[index].coordinate, to: points[index + 1].coordinate)
        }
        if index > 0 {
            return Geo.bearing(from: points[index - 1].coordinate, to: points[index].coordinate)
        }
        return -1
    }
}
