import Foundation

public struct GPXPoint: Sendable, Equatable {
    public var coordinate: Coordinate
    public var elevation: Double?
    public var time: Date?
    /// м/с
    public var speed: Double?
    /// градуси від півночі
    public var course: Double?

    public init(coordinate: Coordinate, elevation: Double? = nil, time: Date? = nil, speed: Double? = nil, course: Double? = nil) {
        self.coordinate = coordinate
        self.elevation = elevation
        self.time = time
        self.speed = speed
        self.course = course
    }
}

public enum GPXError: Error, Equatable {
    case invalidXML
    case empty
}

/// GPX-трек: читання і запис (trkpt з ele, time і extensions speed/course).
public struct GPXTrack: Sendable, Equatable {
    public var name: String?
    public var points: [GPXPoint]

    public init(name: String? = nil, points: [GPXPoint]) {
        self.name = name
        self.points = points
    }

    public static func parse(_ data: Data) throws -> GPXTrack {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw GPXError.invalidXML }
        guard !delegate.points.isEmpty else { throw GPXError.empty }
        return GPXTrack(name: delegate.name, points: delegate.points)
    }

    public func xml() -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="StoneNavigationEmulation" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "  <trk>",
        ]
        if let name { lines.append("    <name>\(name)</name>") }
        lines.append("    <trkseg>")
        for point in points {
            lines.append(#"      <trkpt lat="\#(String(format: "%.7f", point.coordinate.latitude))" lon="\#(String(format: "%.7f", point.coordinate.longitude))">"#)
            if let elevation = point.elevation { lines.append("        <ele>\(String(format: "%.1f", elevation))</ele>") }
            if let time = point.time { lines.append("        <time>\(time.formatted(.iso8601))</time>") }
            if point.speed != nil || point.course != nil {
                lines.append("        <extensions>")
                if let speed = point.speed { lines.append("          <speed>\(String(format: "%.2f", speed))</speed>") }
                if let course = point.course { lines.append("          <course>\(String(format: "%.1f", course))</course>") }
                lines.append("        </extensions>")
            }
            lines.append("      </trkpt>")
        }
        lines += ["    </trkseg>", "  </trk>", "</gpx>", ""]
        return lines.joined(separator: "\n")
    }

    /// Трек уздовж маршруту зі сталою швидкістю: точка кожні `interval` секунд.
    public static func synthesize(along polyline: RoutePolyline, speed: Double, interval: TimeInterval, start: Date, name: String? = nil) -> GPXTrack {
        guard polyline.length > 0, speed > 0, interval > 0 else { return GPXTrack(name: name, points: []) }
        var points: [GPXPoint] = []
        var along = 0.0
        var index = 0
        while true {
            points.append(GPXPoint(
                coordinate: polyline.coordinate(at: along),
                time: start.addingTimeInterval(Double(index) * interval),
                speed: speed,
                course: polyline.bearing(at: along)
            ))
            if polyline.length - along < 0.01 { break }
            along = min(polyline.length, along + speed * interval)
            index += 1
        }
        return GPXTrack(name: name, points: points)
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var name: String?
    var points: [GPXPoint] = []
    private var current: GPXPoint?
    private var text = ""
    private var insideTrack = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch elementName {
        case "trk": insideTrack = true
        case "trkpt", "rtept":
            if let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) {
                current = GPXPoint(coordinate: Coordinate(latitude: lat, longitude: lon))
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "trkpt", "rtept":
            if let current { points.append(current) }
            current = nil
        case "ele": current?.elevation = Double(value)
        case "time": current?.time = Self.parseDate(value)
        case "speed": current?.speed = Double(value)
        case "course": current?.course = Double(value)
        case "name" where insideTrack && current == nil && name == nil: name = value
        default: break
        }
        text = ""
    }

    static func parseDate(_ value: String) -> Date? {
        if let date = try? Date(value, strategy: .iso8601) { return date }
        return try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
