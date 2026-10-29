import Foundation
import NavigationCore

/// Записані фікстури, скопійовані в бандл (папка Fixtures): маршрут, POI і GPX-трек.
enum BundledFixtures {
    static func url(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
    }

    static func route() -> Route? {
        guard let url = url("test_route", "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Route.self, from: data)
    }

    static func pois() -> [PlaceCandidate] {
        guard let url = url("test_pois", "json"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PlaceCandidate].self, from: data)) ?? []
    }

    static func track() -> GPXTrack? {
        guard let url = url("test_track", "gpx"), let data = try? Data(contentsOf: url) else { return nil }
        return try? GPXTrack.parse(data)
    }

    static func destination(for route: Route) -> Place {
        Place(name: "Дарницька площа", subtitle: "Тестовий маршрут", coordinate: route.destination)
    }

    static func origin(for route: Route) -> Place {
        Place(name: "Майдан Незалежності", subtitle: "Початок тестового маршруту", coordinate: route.origin)
    }

    /// Для сценаріїв: місця, які фільтр країн має сховати (за назвою країни) або не дати вибрати (за кодом).
    static let blockedPlaces = [
        Place(name: "Червона площа", subtitle: "Москва, Росія", coordinate: Coordinate(latitude: 55.7539, longitude: 37.6208), countryCode: "RU"),
        Place(name: "Залізничний вокзал", subtitle: "Гомель", coordinate: Coordinate(latitude: 52.4345, longitude: 30.9754), countryCode: "BY"),
    ]
}
