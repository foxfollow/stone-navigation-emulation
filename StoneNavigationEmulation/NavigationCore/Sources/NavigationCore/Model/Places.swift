import Foundation

/// Тип орієнтира біля дороги. Один тип може збирати кілька категорій MapKit (банки й банкомати).
/// Порядок задає порядок фільтрів на екрані.
public enum PlaceCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case gasStation
    case evCharger
    case store
    case foodMarket
    case pharmacy
    case cafe
    case restaurant
    case postOffice
    case bank
    case hotel
    case hospital
    case carService
    case parking
    case police
    case school
    case park
    case sight

    public var id: String { rawValue }

    /// Назва фільтра.
    public var title: String {
        switch self {
        case .gasStation: "АЗС"
        case .evCharger: "Зарядки"
        case .store: "Магазини"
        case .foodMarket: "Продукти"
        case .pharmacy: "Аптеки"
        case .cafe: "Кафе"
        case .restaurant: "Ресторани"
        case .postOffice: "Пошта"
        case .bank: "Банки"
        case .hotel: "Готелі"
        case .hospital: "Лікарні"
        case .carService: "СТО"
        case .parking: "Парковки"
        case .police: "Поліція"
        case .school: "Школи"
        case .park: "Парки"
        case .sight: "Пам'ятки"
        }
    }

    /// Назва одного місця.
    public var singular: String {
        switch self {
        case .gasStation: "АЗС"
        case .evCharger: "Зарядна станція"
        case .store: "Магазин"
        case .foodMarket: "Продуктовий магазин"
        case .pharmacy: "Аптека"
        case .cafe: "Кафе"
        case .restaurant: "Ресторан"
        case .postOffice: "Пошта"
        case .bank: "Банк"
        case .hotel: "Готель"
        case .hospital: "Лікарня"
        case .carService: "СТО"
        case .parking: "Парковка"
        case .police: "Поліція"
        case .school: "Школа"
        case .park: "Парк"
        case .sight: "Пам'ятка"
        }
    }

    /// SF Symbol для значка.
    public var symbolName: String {
        switch self {
        case .gasStation: "fuelpump.fill"
        case .evCharger: "bolt.car.fill"
        case .store: "bag.fill"
        case .foodMarket: "cart.fill"
        case .pharmacy: "cross.case.fill"
        case .cafe: "cup.and.saucer.fill"
        case .restaurant: "fork.knife"
        case .postOffice: "shippingbox.fill"
        case .bank: "banknote.fill"
        case .hotel: "bed.double.fill"
        case .hospital: "cross.fill"
        case .carService: "wrench.and.screwdriver.fill"
        case .parking: "parkingsign"
        case .police: "shield.fill"
        case .school: "graduationcap.fill"
        case .park: "tree.fill"
        case .sight: "building.columns.fill"
        }
    }

    /// Чи показувати тип, поки водій не змінив фільтри. Що більше типів увімкнено, то менше місць
    /// кожного типу вміщає одна відповідь MapKit, тож за замовчуванням лише помітні з дороги.
    public var isShownByDefault: Bool {
        switch self {
        case .gasStation, .store, .foodMarket, .pharmacy, .cafe, .restaurant, .postOffice: true
        case .evCharger, .bank, .hotel, .hospital, .carService, .parking, .police, .school, .park, .sight: false
        }
    }
}

/// Місце від пошуку, ще не прив'язане до маршруту.
public struct PlaceCandidate: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var category: PlaceCategory
    public var coordinate: Coordinate
    /// MKMapItem.Identifier.rawValue для системної картки «Детальніше».
    public var mapItemIdentifier: String?
    /// Код країни ISO 3166-1 («UA»), якщо постачальник його знає.
    public var countryCode: String?

    public init(id: String, name: String, category: PlaceCategory, coordinate: Coordinate, mapItemIdentifier: String? = nil, countryCode: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.coordinate = coordinate
        self.mapItemIdentifier = mapItemIdentifier
        self.countryCode = countryCode
    }
}

/// Орієнтир у коридорі маршруту.
public struct Landmark: Codable, Sendable, Hashable, Identifiable {
    public var place: PlaceCandidate
    /// Позиція проєкції на маршрут від початку, метри.
    public var along: Double
    /// Відстань від лінії дороги, метри.
    public var offset: Double
    public var side: RoadSide

    public var id: String { place.id }

    public init(place: PlaceCandidate, along: Double, offset: Double, side: RoadSide) {
        self.place = place
        self.along = along
        self.offset = offset
        self.side = side
    }
}

/// Пункт призначення або результат пошуку.
public struct Place: Codable, Sendable, Hashable {
    public var name: String
    public var subtitle: String?
    public var coordinate: Coordinate
    public var mapItemIdentifier: String?
    /// Код країни ISO 3166-1 («UA»), якщо постачальник його знає.
    public var countryCode: String?

    public init(name: String, subtitle: String? = nil, coordinate: Coordinate, mapItemIdentifier: String? = nil, countryCode: String? = nil) {
        self.name = name
        self.subtitle = subtitle
        self.coordinate = coordinate
        self.mapItemIdentifier = mapItemIdentifier
        self.countryCode = countryCode
    }
}

/// Підказка автодоповнення пошуку.
public struct PlaceSuggestion: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String

    public init(id: String, title: String, subtitle: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

/// Прямокутний регіон у градусах.
public struct GeoRegion: Codable, Sendable, Equatable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    /// Регіон, що покриває всі точки з запасом `padding` метрів з кожного боку.
    public init(covering coordinates: [Coordinate], padding: Double) {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let metersPerDegree = Geo.earthRadius * .pi / 180
        let latPad = padding / metersPerDegree
        let lonPad = padding / (metersPerDegree * max(0.01, cos((minLat + maxLat) / 2 * .pi / 180)))
        self.init(minLatitude: minLat - latPad, maxLatitude: maxLat + latPad,
                  minLongitude: (longitudes.min() ?? 0) - lonPad, maxLongitude: (longitudes.max() ?? 0) + lonPad)
    }

    public var center: Coordinate {
        Coordinate(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }

    public var latitudeDelta: Double { maxLatitude - minLatitude }
    public var longitudeDelta: Double { maxLongitude - minLongitude }

    public func contains(_ coordinate: Coordinate) -> Bool {
        (minLatitude...maxLatitude).contains(coordinate.latitude) && (minLongitude...maxLongitude).contains(coordinate.longitude)
    }
}
