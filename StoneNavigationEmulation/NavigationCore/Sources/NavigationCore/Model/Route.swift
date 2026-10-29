import Foundation

/// Крок покрокової вказівки (аналог MKRoute.Step). Як і в MapKit, `distance` це шлях до маневру,
/// а саму вказівку виконують у кінці polyline кроку: «через 488 м поверніть управо на Грушевського».
public struct RouteStep: Codable, Sendable, Equatable {
    public var instructions: String
    public var distance: Double
    public var notice: String?
    public var coordinates: [Coordinate]

    public init(instructions: String, distance: Double, notice: String? = nil, coordinates: [Coordinate]) {
        self.instructions = instructions
        self.distance = distance
        self.notice = notice
        self.coordinates = coordinates
    }
}

public enum TurnDirection: String, Sendable {
    case straight, slightLeft, slightRight, left, right, uTurn, arrive

    init(angle: Double?) {
        guard let angle else {
            self = .arrive
            return
        }
        switch abs(angle) {
        case ..<20: self = .straight
        case ..<45: self = angle > 0 ? .slightRight : .slightLeft
        case ..<150: self = angle > 0 ? .right : .left
        default: self = .uTurn
        }
    }

    var fallbackInstruction: String {
        switch self {
        case .straight: "Рухайтеся прямо"
        case .slightLeft: "Тримайтеся лівіше"
        case .slightRight: "Тримайтеся правіше"
        case .left: "Поверніть ліворуч"
        case .right: "Поверніть праворуч"
        case .uTurn: "Розверніться"
        case .arrive: "Пункт призначення"
        }
    }
}

/// Маневр у точці маршруту: кінець кроку з індексом `id`.
public struct Maneuver: Sendable, Equatable, Identifiable {
    public let id: Int
    public let along: Double
    public let coordinate: Coordinate
    public let instructions: String
    /// Зміна курсу в градусах: додатна праворуч, від'ємна ліворуч; nil у кінці маршруту.
    public let turnAngle: Double?
    public let isArrival: Bool

    public var direction: TurnDirection { isArrival ? .arrive : TurnDirection(angle: turnAngle) }

    /// Чи це справжній поворот, а не «їдьте далі».
    public var isTurn: Bool {
        guard let turnAngle, !isArrival else { return false }
        return abs(turnAngle) >= 20
    }

    public var spokenInstruction: String {
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? direction.fallbackInstruction : trimmed
    }
}

/// Маршрут з polyline і кроками. Зберігається на диску, щоб навігація працювала без інтернету.
public struct Route: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let origin: Coordinate
    public let destination: Coordinate
    public let stops: [Coordinate]
    public let coordinates: [Coordinate]
    public let steps: [RouteStep]
    /// Відстань за даними постачальника маршруту, метри.
    public let distance: Double
    /// Очікуваний час у дорозі за даними постачальника (MKRoute.expectedTravelTime).
    public let expectedTravelTime: TimeInterval?

    public let polyline: RoutePolyline
    public let maneuvers: [Maneuver]

    enum CodingKeys: String, CodingKey {
        case id, name, origin, destination, stops, coordinates, steps, distance, expectedTravelTime
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        origin: Coordinate,
        destination: Coordinate,
        stops: [Coordinate] = [],
        coordinates: [Coordinate],
        steps: [RouteStep],
        distance: Double? = nil,
        expectedTravelTime: TimeInterval?
    ) {
        let polyline = RoutePolyline(coordinates)
        self.id = id
        self.name = name
        self.origin = origin
        self.destination = destination
        self.stops = stops
        self.coordinates = coordinates
        self.steps = steps
        self.distance = distance ?? polyline.length
        self.expectedTravelTime = expectedTravelTime
        self.polyline = polyline
        self.maneuvers = Route.makeManeuvers(steps: steps, polyline: polyline)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            origin: try container.decode(Coordinate.self, forKey: .origin),
            destination: try container.decode(Coordinate.self, forKey: .destination),
            stops: try container.decodeIfPresent([Coordinate].self, forKey: .stops) ?? [],
            coordinates: try container.decode([Coordinate].self, forKey: .coordinates),
            steps: try container.decode([RouteStep].self, forKey: .steps),
            distance: try container.decodeIfPresent(Double.self, forKey: .distance),
            expectedTravelTime: try container.decodeIfPresent(TimeInterval.self, forKey: .expectedTravelTime)
        )
    }

    /// Середня швидкість маршруту: відстань поділена на очікуваний час, м/с.
    public var averageSpeed: Double? {
        guard let expectedTravelTime, expectedTravelTime > 0, distance > 0 else { return nil }
        return distance / expectedTravelTime
    }

    /// Перший маневр попереду від дистанції.
    public func nextManeuver(after along: Double) -> Maneuver? {
        maneuvers.first { $0.along > along + 0.5 }
    }

    static func makeManeuvers(steps: [RouteStep], polyline: RoutePolyline) -> [Maneuver] {
        guard polyline.points.count > 1 else { return [] }
        var result: [Maneuver] = []
        var cursor = 0.0
        for (index, step) in steps.enumerated() where index > 0 {
            guard let last = step.coordinates.last,
                  let projection = polyline.project(last, in: cursor...polyline.length) else { continue }
            cursor = projection.along
            let isArrival = index == steps.count - 1 || polyline.length - projection.along < 5
            result.append(Maneuver(
                id: index,
                along: projection.along,
                coordinate: polyline.coordinate(at: projection.along),
                instructions: step.instructions,
                turnAngle: isArrival ? nil : turnAngle(at: projection.along, polyline: polyline),
                isArrival: isArrival
            ))
        }
        return result
    }

    /// Зміна курсу маршруту в точці: порівнюємо напрямок 20 м до і 20 м після.
    static func turnAngle(at along: Double, polyline: RoutePolyline) -> Double? {
        let sample = 20.0
        let here = polyline.coordinate(at: along)
        let before = polyline.coordinate(at: along - sample)
        let after = polyline.coordinate(at: along + sample)
        guard Geo.distance(before, here) > 1, Geo.distance(here, after) > 1 else { return 0 }
        let incoming = Geo.bearing(from: before, to: here)
        let outgoing = Geo.bearing(from: here, to: after)
        return Geo.normalizedAngle(outgoing - incoming)
    }
}
