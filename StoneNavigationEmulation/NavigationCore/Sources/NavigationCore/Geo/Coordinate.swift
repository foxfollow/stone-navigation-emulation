import Foundation

/// Географічна точка. Своя, а не CLLocationCoordinate2D, щоб ядро тестувалось на macOS без CoreLocation.
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum Geo {
    public static let earthRadius: Double = 6_371_008.8

    /// Відстань за формулою гаверсинуса, метри.
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Азимут від `a` до `b` у градусах 0..<360, за годинниковою стрілкою від півночі.
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Точка на відстані `distance` метрів за азимутом `bearing`.
    public static func destination(from origin: Coordinate, bearing: Double, distance: Double) -> Coordinate {
        let angular = distance / earthRadius
        let theta = bearing * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return Coordinate(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    /// Кут у діапазоні (-180, 180].
    public static func normalizedAngle(_ degrees: Double) -> Double {
        var angle = degrees.truncatingRemainder(dividingBy: 360)
        if angle > 180 { angle -= 360 }
        if angle <= -180 { angle += 360 }
        return angle
    }
}

/// Плоска (рівнопроміжна) проєкція навколо опорної точки: x на схід, y на північ, метри.
/// Для відрізків маршруту довжиною до кількох кілометрів похибка нехтовно мала.
public struct LocalProjection: Sendable {
    public let origin: Coordinate
    private let metersPerDegreeLatitude: Double
    private let metersPerDegreeLongitude: Double

    public init(origin: Coordinate) {
        self.origin = origin
        metersPerDegreeLatitude = Geo.earthRadius * .pi / 180
        metersPerDegreeLongitude = metersPerDegreeLatitude * cos(origin.latitude * .pi / 180)
    }

    public func project(_ coordinate: Coordinate) -> (x: Double, y: Double) {
        ((coordinate.longitude - origin.longitude) * metersPerDegreeLongitude,
         (coordinate.latitude - origin.latitude) * metersPerDegreeLatitude)
    }

    public func unproject(x: Double, y: Double) -> Coordinate {
        Coordinate(latitude: origin.latitude + y / metersPerDegreeLatitude,
                   longitude: origin.longitude + x / metersPerDegreeLongitude)
    }
}
