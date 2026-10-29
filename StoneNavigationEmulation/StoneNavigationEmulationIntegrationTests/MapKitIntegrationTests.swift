import Foundation
import NavigationCore
import Testing
@testable import StoneNavigationEmulation

extension Tag {
    /// Тест іде в мережу MapKit. Такий тест у проєкті один, решта працює на записаних фікстурах.
    @Tag static var network: Self
}

@Suite("Інтеграція з MapKit (мережа)", .tags(.network), .serialized)
@MainActor
struct MapKitIntegrationTests {
    static let origin = Coordinate(latitude: 50.4501, longitude: 30.5234)       // Майдан Незалежності
    static let destination = Coordinate(latitude: 50.4565, longitude: 30.6136)  // Дарницька площа

    /// Справжні MKDirections і MKLocalPointsOfInterestRequest перетворюються на типи NavigationCore.
    /// Із `RECORD_FIXTURES_DIR` відповідь записується у фікстури тестів.
    @Test("MapKit: маршрут із кроками і орієнтири вздовж нього у форматі NavigationCore")
    func liveRouteAndLandmarks() async throws {
        let route = try await MapKitRouteProvider().route(from: Self.origin, to: Self.destination, via: [])
        #expect(route.polyline.length > 3000)
        #expect(route.steps.count > 3)
        #expect(route.averageSpeed != nil)
        #expect(route.maneuvers.contains { $0.isTurn })
        #expect(route.steps.contains { !$0.instructions.isEmpty })

        let search = MapKitPlaceSearch()
        var candidates: [PlaceCandidate] = []
        // Ділянками по 2 км: так регіон запиту не надто великий і орієнтирів повертається більше.
        let segment = 2000.0
        var start = 0.0
        while start < route.polyline.length {
            let region = route.polyline.region(for: start...(start + segment), padding: 300)
            let found = try await search.pointsOfInterest(in: region, categories: Set(PlaceCategory.allCases))
            candidates += found.filter { item in !candidates.contains { $0.id == item.id } }
            start += segment
        }
        #expect(!candidates.isEmpty)
        // Нові типи теж приходять: у центрі Києва є аптеки, кафе, ресторани, банки.
        let counts = Dictionary(grouping: candidates, by: \.category).mapValues(\.count)
        print("Типи орієнтирів від MapKit: \(counts.map { "\($0.key.rawValue) \($0.value)" }.sorted().joined(separator: ", "))")
        #expect(Set(counts.keys).subtracting([.gasStation, .store, .foodMarket]).count >= 3)
        let landmarks = LandmarkSelector.select(candidates, polyline: route.polyline, corridor: 2000)
        #expect(!landmarks.isEmpty)

        if let directory = ProcessInfo.processInfo.environment["RECORD_FIXTURES_DIR"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let recorded = Route(
                id: "test-route-kyiv",
                name: route.name,
                origin: route.origin,
                destination: route.destination,
                coordinates: route.coordinates,
                steps: route.steps,
                distance: route.distance,
                expectedTravelTime: route.expectedTravelTime
            )
            let folder = URL(fileURLWithPath: directory)
            try encoder.encode(recorded).write(to: folder.appending(path: "test_route.json"))
            try encoder.encode(candidates).write(to: folder.appending(path: "test_pois.json"))
            print("Записано фікстури: \(route.steps.count) кроків, \(route.coordinates.count) точок, \(candidates.count) POI")
        }
    }
}
