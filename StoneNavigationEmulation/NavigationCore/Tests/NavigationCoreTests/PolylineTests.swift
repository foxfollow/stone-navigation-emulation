import Foundation
import Testing
@testable import NavigationCore

@Suite("Рух точки по polyline")
struct PolylineTests {
    let route = TestRoute.make()

    @Test("Довжина ламаної дорівнює сумі відрізків")
    func length() {
        #expect(abs(route.polyline.length - 2000) < 1)
    }

    @Test("Точка на дистанції лежить на маршруті", arguments: [
        (0.0, TestRoute.start),
        (500.0, Geo.destination(from: TestRoute.start, bearing: 0, distance: 500)),
        (1000.0, TestRoute.corner),
        (1500.0, Geo.destination(from: TestRoute.corner, bearing: 90, distance: 500)),
        (2000.0, TestRoute.end),
    ])
    func coordinateAtDistance(along: Double, expected: Coordinate) {
        #expect(Geo.distance(route.polyline.coordinate(at: along), expected) < 0.5)
    }

    @Test("Рух по маршруту крок за кроком проходить поворот і доходить до кінця")
    func movingPointPassesCorner() {
        var along = 0.0
        var previous = route.polyline.coordinate(at: along)
        var travelled = 0.0
        while along < route.polyline.length {
            along += 37
            let next = route.polyline.coordinate(at: along)
            travelled += Geo.distance(previous, next)
            previous = next
        }
        #expect(Geo.distance(previous, TestRoute.end) < 0.5)
        // Відстань по прямих між сусідніми точками не більша за довжину маршруту і майже дорівнює їй.
        #expect(travelled <= route.polyline.length + 0.5)
        #expect(travelled > route.polyline.length - 15)
    }

    @Test("Дистанція поза маршрутом обрізається до початку і кінця")
    func clamps() {
        #expect(Geo.distance(route.polyline.coordinate(at: -100), TestRoute.start) < 0.01)
        #expect(Geo.distance(route.polyline.coordinate(at: 9999), TestRoute.end) < 0.01)
    }

    @Test("Курс маршруту: північ до повороту, схід після")
    func bearing() {
        #expect(abs(route.polyline.bearing(at: 500)) < 0.5)
        #expect(abs(route.polyline.bearing(at: 1500) - 90) < 0.5)
    }

    @Test("Проєкція: дистанція, відстань від дороги і бік")
    func projection() throws {
        let left = try #require(route.polyline.project(TestRoute.point(along: 400, offset: -30)))
        #expect(abs(left.along - 400) < 0.5)
        #expect(abs(left.offset - 30) < 0.5)
        #expect(left.side == .left)

        let right = try #require(route.polyline.project(TestRoute.point(along: 1500, offset: 20)))
        #expect(abs(right.along - 1500) < 0.5)
        #expect(abs(right.offset - 20) < 0.5)
        #expect(right.side == .right)
    }

    @Test("Проєкція в обмеженому діапазоні не виходить за його межі")
    func projectionInRange() throws {
        let projection = try #require(route.polyline.project(TestRoute.point(along: 1500), in: 0...800))
        #expect(abs(projection.along - 800) < 0.5)
        #expect(projection.offset > 500)
    }

    @Test("Зріз маршруту має точні кінці")
    func slice() {
        let slice = route.polyline.slice(250...1250)
        #expect(Geo.distance(slice.first!, route.polyline.coordinate(at: 250)) < 0.01)
        #expect(Geo.distance(slice.last!, route.polyline.coordinate(at: 1250)) < 0.01)
        #expect(slice.contains { Geo.distance($0, TestRoute.corner) < 0.01 })
    }

    @Test("Маневри: поворот праворуч на 1000 м, прибуття в кінці")
    func maneuvers() throws {
        #expect(route.maneuvers.count == 2)
        let turn = try #require(route.maneuvers.first { $0.id == 1 })
        #expect(abs(turn.along - 1000) < 0.5)
        #expect(turn.direction == .right)
        #expect(turn.isTurn)
        let arrival = try #require(route.maneuvers.last)
        #expect(arrival.isArrival)
        #expect(route.averageSpeed == 10)
    }

    @Test("Route переживає кодування JSON разом із маневрами")
    func codable() throws {
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(Route.self, from: data)
        #expect(decoded == route)
        #expect(decoded.maneuvers.count == route.maneuvers.count)
    }
}
