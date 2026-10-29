import Foundation

/// Бік дороги відносно напрямку руху по маршруту.
public enum RoadSide: String, Codable, Sendable {
    case left
    case right

    public var title: String { self == .left ? "ліворуч" : "праворуч" }
}

/// Результат проєкції точки на лінію маршруту.
public struct RouteProjection: Sendable, Equatable {
    /// Дистанція від початку маршруту до найближчої точки на лінії, метри.
    public var along: Double
    /// Відстань від точки до лінії маршруту, метри.
    public var offset: Double
    public var side: RoadSide
    public var point: Coordinate
    public var segmentIndex: Int
}

/// Ламана маршруту з накопиченими дистанціями: рух точки по маршруту і прив'язка до дороги.
public struct RoutePolyline: Sendable, Equatable {
    public let points: [Coordinate]
    /// `cumulative[i]` це дистанція від початку до `points[i]`.
    public let cumulative: [Double]

    public init(_ coordinates: [Coordinate]) {
        var unique: [Coordinate] = []
        for coordinate in coordinates {
            if let last = unique.last, Geo.distance(last, coordinate) < 0.01 { continue }
            unique.append(coordinate)
        }
        var cumulative: [Double] = unique.isEmpty ? [] : [0]
        for index in unique.indices.dropFirst() {
            cumulative.append(cumulative[index - 1] + Geo.distance(unique[index - 1], unique[index]))
        }
        self.points = unique
        self.cumulative = cumulative
    }

    public var length: Double { cumulative.last ?? 0 }
    public var isEmpty: Bool { points.isEmpty }

    public func clamp(_ along: Double) -> Double {
        min(max(along, 0), length)
    }

    /// Індекс відрізка `[i, i+1]`, на якому лежить дистанція.
    public func segmentIndex(at along: Double) -> Int {
        guard points.count > 1 else { return 0 }
        let target = clamp(along)
        var low = 0
        var high = cumulative.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if cumulative[mid] <= target { low = mid } else { high = mid }
        }
        return low
    }

    /// Точка на маршруті на заданій дистанції від початку.
    public func coordinate(at along: Double) -> Coordinate {
        guard let first = points.first else { return Coordinate(latitude: 0, longitude: 0) }
        guard points.count > 1 else { return first }
        let target = clamp(along)
        let index = segmentIndex(at: target)
        let segmentLength = cumulative[index + 1] - cumulative[index]
        let t = segmentLength > 0 ? (target - cumulative[index]) / segmentLength : 0
        let a = points[index]
        let b = points[index + 1]
        return Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                          longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// Курс маршруту в точці, градуси від півночі.
    public func bearing(at along: Double) -> Double {
        guard points.count > 1 else { return 0 }
        let index = segmentIndex(at: along)
        return Geo.bearing(from: points[index], to: points[index + 1])
    }

    /// Найближча точка лінії маршруту, за потреби лише в межах `range`.
    public func project(_ coordinate: Coordinate, in range: ClosedRange<Double>? = nil) -> RouteProjection? {
        guard points.count > 1 else {
            guard let only = points.first else { return nil }
            return RouteProjection(along: 0, offset: Geo.distance(only, coordinate), side: .right, point: only, segmentIndex: 0)
        }
        let lower = clamp(range?.lowerBound ?? 0)
        let upper = max(lower, clamp(range?.upperBound ?? length))
        var best: RouteProjection?
        for index in 0..<(points.count - 1) {
            let start = cumulative[index]
            let end = cumulative[index + 1]
            let segmentLength = end - start
            guard end >= lower, start <= upper, segmentLength > 0 else { continue }

            let projection = LocalProjection(origin: points[index])
            let b = projection.project(points[index + 1])
            let p = projection.project(coordinate)
            let lengthSquared = b.x * b.x + b.y * b.y
            let tMin = max(0, (lower - start) / segmentLength)
            let tMax = min(1, (upper - start) / segmentLength)
            var t = lengthSquared > 0 ? (p.x * b.x + p.y * b.y) / lengthSquared : 0
            t = min(max(t, tMin), tMax)
            let footX = b.x * t
            let footY = b.y * t
            let offset = hypot(p.x - footX, p.y - footY)
            if let current = best, current.offset <= offset { continue }
            let cross = b.x * p.y - b.y * p.x
            best = RouteProjection(
                along: start + segmentLength * t,
                offset: offset,
                side: cross > 0 ? .left : .right,
                point: projection.unproject(x: footX, y: footY),
                segmentIndex: index
            )
        }
        return best
    }

    /// Частина маршруту між двома дистанціями, включно з точними кінцями.
    public func slice(_ range: ClosedRange<Double>) -> [Coordinate] {
        guard points.count > 1 else { return points }
        let lower = clamp(range.lowerBound)
        let upper = max(lower, clamp(range.upperBound))
        var result = [coordinate(at: lower)]
        for index in points.indices where cumulative[index] > lower && cumulative[index] < upper {
            result.append(points[index])
        }
        result.append(coordinate(at: upper))
        return result
    }

    /// Прямокутний регіон, що покриває частину маршруту з запасом `padding` метрів.
    public func region(for range: ClosedRange<Double>, padding: Double) -> GeoRegion {
        GeoRegion(covering: slice(range), padding: padding)
    }
}
