import MapKit
import NavigationCore

/// Автомобільний маршрут через MKDirections. Зупинки йдуть окремими плечима і зшиваються.
/// MKError.loadingThrottled перетворюється на RouteProviderError.throttled, далі backoff і кеш у сесії.
@MainActor
final class MapKitRouteProvider: RouteProvider {
    func route(from origin: Coordinate, to destination: Coordinate, via stops: [Coordinate]) async throws -> Route {
        let points = [origin] + stops + [destination]
        var legs: [MapKitConversions.Leg] = []
        for (start, end) in zip(points, points.dropFirst()) {
            legs.append(try await Self.leg(from: start, to: end))
        }
        return MapKitConversions.route(legs: legs, origin: origin, destination: destination, stops: stops)
    }

    /// Запит і перетворення поза головним актором: назовні виходять лише Sendable-дані.
    nonisolated private static func leg(from start: Coordinate, to end: Coordinate) async throws -> MapKitConversions.Leg {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: start.clLocation, address: nil)
        request.destination = MKMapItem(location: end.clLocation, address: nil)
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let best = response.routes.first else { throw RouteProviderError.noRoute }
            return MapKitConversions.leg(best)
        } catch let error as MKError {
            switch error.code {
            case .loadingThrottled: throw RouteProviderError.throttled(retryAfter: nil)
            case .directionsNotFound, .placemarkNotFound: throw RouteProviderError.noRoute
            default: throw RouteProviderError.failed(error.localizedDescription)
            }
        }
    }
}
