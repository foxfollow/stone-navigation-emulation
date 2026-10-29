import MapKit
import NavigationCore

/// Перетворення MapKit-типів на типи NavigationCore. Google-версія з'явиться поруч зі своїми перетвореннями.
enum MapKitConversions {
    /// Одне плече маршруту в Sendable-формі, щоб передати його між акторами.
    struct Leg: Sendable {
        let name: String
        let coordinates: [Coordinate]
        let steps: [RouteStep]
        let distance: Double
        let expectedTravelTime: TimeInterval
    }

    static func coordinates(_ polyline: MKPolyline) -> [Coordinate] {
        var buffer = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&buffer, range: NSRange(location: 0, length: polyline.pointCount))
        return buffer.map(Coordinate.init)
    }

    static func leg(_ route: MKRoute) -> Leg {
        Leg(
            name: route.name,
            coordinates: coordinates(route.polyline),
            steps: route.steps.map { step in
                RouteStep(instructions: step.instructions, distance: step.distance, notice: step.notice, coordinates: coordinates(step.polyline))
            },
            distance: route.distance,
            expectedTravelTime: route.expectedTravelTime
        )
    }

    /// Зшити плечі (старт → зупинки → фініш) в один маршрут.
    static func route(legs: [Leg], origin: Coordinate, destination: Coordinate, stops: [Coordinate]) -> Route {
        var coordinates: [Coordinate] = []
        var steps: [RouteStep] = []
        for (index, leg) in legs.enumerated() {
            coordinates += index == 0 ? leg.coordinates : Array(leg.coordinates.dropFirst())
            // Перший крок кожного плеча порожній («початок»), лишаємо його лише для першого.
            steps += index == 0 ? leg.steps : leg.steps.filter { !$0.instructions.isEmpty }
        }
        return Route(
            name: legs.map(\.name).filter { !$0.isEmpty }.joined(separator: " → "),
            origin: origin,
            destination: destination,
            stops: stops,
            coordinates: coordinates,
            steps: steps,
            distance: legs.reduce(0) { $0 + $1.distance },
            expectedTravelTime: legs.reduce(0) { $0 + $1.expectedTravelTime }
        )
    }

    static func category(_ category: MKPointOfInterestCategory?) -> PlaceCategory? {
        guard let category else { return nil }
        return PlaceCategory.allCases.first { mapKitCategories($0).contains(category) }
    }

    /// Категорії MapKit, які збирає тип орієнтира: банки разом із банкоматами, кафе з пекарнями.
    static func mapKitCategories(_ category: PlaceCategory) -> [MKPointOfInterestCategory] {
        switch category {
        case .gasStation: [.gasStation]
        case .evCharger: [.evCharger]
        case .store: [.store]
        case .foodMarket: [.foodMarket]
        case .pharmacy: [.pharmacy]
        case .cafe: [.cafe, .bakery]
        case .restaurant: [.restaurant]
        case .postOffice: [.postOffice]
        case .bank: [.bank, .atm]
        case .hotel: [.hotel]
        case .hospital: [.hospital]
        case .carService: [.automotiveRepair]
        case .parking: [.parking]
        case .police: [.police]
        case .school: [.school, .university]
        case .park: [.park]
        case .sight: [.landmark, .museum, .nationalMonument, .castle]
        }
    }

    static func candidate(_ item: MKMapItem) -> PlaceCandidate? {
        guard let category = category(item.pointOfInterestCategory) else { return nil }
        let coordinate = Coordinate(item.location.coordinate)
        let identifier = item.identifier?.rawValue
        return PlaceCandidate(
            id: identifier ?? "\(coordinate.latitude),\(coordinate.longitude)",
            name: item.name ?? category.singular,
            category: category,
            coordinate: coordinate,
            mapItemIdentifier: identifier,
            countryCode: countryCode(item)
        )
    }

    static func place(_ item: MKMapItem) -> Place {
        Place(
            name: item.name ?? "Місце",
            subtitle: item.address?.shortAddress,
            coordinate: Coordinate(item.location.coordinate),
            mapItemIdentifier: item.identifier?.rawValue,
            countryCode: countryCode(item)
        )
    }

    /// Код країни ISO 3166-1 з адреси місця («UA»), за ним фільтруються Росія і Білорусь.
    static func countryCode(_ item: MKMapItem) -> String? {
        item.addressRepresentations?.region?.identifier
    }

    static func placeError(_ error: any Error) -> PlaceSearchError {
        guard let error = error as? MKError else { return .failed(error.localizedDescription) }
        switch error.code {
        case .loadingThrottled: return .throttled(retryAfter: nil)
        case .placemarkNotFound: return .notFound
        default: return .failed(error.localizedDescription)
        }
    }
}
