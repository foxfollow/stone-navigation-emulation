import Foundation

public enum SettingSection: String, CaseIterable, Sendable, Identifiable {
    case movement, switching, spoofing, route, voice, landmarks, screen, sensors

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .movement: "Рух"
        case .switching: "Перемикання GPS"
        case .spoofing: "Підміна GPS"
        case .route: "Маршрут"
        case .voice: "Голос"
        case .landmarks: "Орієнтири"
        case .screen: "Екран"
        case .sensors: "Датчики"
        }
    }
}

/// Опис числового налаштування: стандартне значення, межі, крок кнопок.
public struct SettingSpec: Sendable, Equatable {
    public let title: String
    public let unit: String
    public let defaultValue: Double
    public let range: ClosedRange<Double>
    public let step: Double
    public let section: SettingSection

    public func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Усі числа зі специфікації. Значення в одиницях, які бачить користувач (км/год, м, с, км, °).
public enum SettingKey: String, CaseIterable, Sendable, Identifiable {
    case defaultSpeedKmh, speedStepKmh, shiftStepMeters, updateInterval
    case enterAccuracy, staleAge, returnAccuracy, returnDuration
    case spoofDistance, impossibleSpeedKmh, courseJumpDegrees, courseMinSpeedKmh, turnProximity, promptCooldown
    case offRouteThreshold, transitionDuration
    case voiceFarDistance, voiceNearDistance, voiceAtTurnDistance
    case landmarkSegmentKm, landmarkCorridor
    case dimAfter
    case gyroTurnDegrees, turnSnapMaxDistance

    public var id: String { rawValue }

    public var spec: SettingSpec {
        switch self {
        case .defaultSpeedKmh:
            SettingSpec(title: "Швидкість за замовчуванням", unit: "км/год", defaultValue: 50, range: 10...130, step: 5, section: .movement)
        case .speedStepKmh:
            SettingSpec(title: "Крок кнопок + і −", unit: "км/год", defaultValue: 5, range: 1...20, step: 1, section: .movement)
        case .shiftStepMeters:
            SettingSpec(title: "Зсув Вперед і Назад", unit: "м", defaultValue: 50, range: 10...500, step: 10, section: .movement)
        case .updateInterval:
            SettingSpec(title: "Оновлення позиції", unit: "с", defaultValue: 1, range: 0.5...5, step: 0.5, section: .movement)
        case .enterAccuracy:
            SettingSpec(title: "Розрахунковий режим, якщо точність гірша за", unit: "м", defaultValue: 100, range: 30...500, step: 10, section: .switching)
        case .staleAge:
            SettingSpec(title: "…або точка старша за", unit: "с", defaultValue: 3, range: 1...30, step: 1, section: .switching)
        case .returnAccuracy:
            SettingSpec(title: "Повертати GPS, якщо точність краща за", unit: "м", defaultValue: 30, range: 5...100, step: 5, section: .switching)
        case .returnDuration:
            SettingSpec(title: "…протягом", unit: "с", defaultValue: 5, range: 1...30, step: 1, section: .switching)
        case .spoofDistance:
            SettingSpec(title: "Межа відстані до розрахункової позиції", unit: "м", defaultValue: 500, range: 100...5000, step: 50, section: .spoofing)
        case .impossibleSpeedKmh:
            SettingSpec(title: "Неможлива швидкість між точками", unit: "км/год", defaultValue: 200, range: 120...400, step: 10, section: .spoofing)
        case .courseJumpDegrees:
            SettingSpec(title: "Різка зміна курсу", unit: "°", defaultValue: 60, range: 20...180, step: 5, section: .spoofing)
        case .courseMinSpeedKmh:
            SettingSpec(title: "Перевіряти курс від швидкості", unit: "км/год", defaultValue: 20, range: 5...80, step: 5, section: .spoofing)
        case .turnProximity:
            SettingSpec(title: "Поворот на маршруті поруч, якщо ближче", unit: "м", defaultValue: 50, range: 10...300, step: 10, section: .spoofing)
        case .promptCooldown:
            SettingSpec(title: "Повторний запит про GPS через", unit: "с", defaultValue: 60, range: 10...600, step: 10, section: .spoofing)
        case .offRouteThreshold:
            SettingSpec(title: "Відхилення для «Перебудувати»", unit: "м", defaultValue: 50, range: 20...300, step: 10, section: .route)
        case .transitionDuration:
            SettingSpec(title: "Плавний перехід", unit: "с", defaultValue: 2, range: 0...10, step: 0.5, section: .route)
        case .voiceFarDistance:
            SettingSpec(title: "Перша підказка за", unit: "м", defaultValue: 300, range: 50...2000, step: 50, section: .voice)
        case .voiceNearDistance:
            SettingSpec(title: "Друга підказка за", unit: "м", defaultValue: 100, range: 50...2000, step: 50, section: .voice)
        case .voiceAtTurnDistance:
            SettingSpec(title: "Підказка «на повороті» за", unit: "м", defaultValue: 30, range: 5...100, step: 5, section: .voice)
        case .landmarkSegmentKm:
            SettingSpec(title: "Довжина ділянки наперед", unit: "км", defaultValue: 10, range: 2...50, step: 1, section: .landmarks)
        case .landmarkCorridor:
            SettingSpec(title: "Макс. відстань від дороги", unit: "м", defaultValue: 50, range: 10...2000, step: 10, section: .landmarks)
        case .dimAfter:
            SettingSpec(title: "Затемнення через", unit: "с", defaultValue: 30, range: 10...300, step: 10, section: .screen)
        case .gyroTurnDegrees:
            SettingSpec(title: "Гіроскоп: поворот від", unit: "°", defaultValue: 45, range: 20...120, step: 5, section: .sensors)
        case .turnSnapMaxDistance:
            SettingSpec(title: "Підтягувати до повороту в межах", unit: "м", defaultValue: 300, range: 50...2000, step: 50, section: .sensors)
        }
    }
}

public enum SettingToggle: String, CaseIterable, Sendable, Identifiable {
    case voiceEnabled, keepScreenOn, dimEnabled, motionEnabled
    case showGasStations, showEVChargers, showStores, showFoodMarkets, showPharmacies, showCafes, showRestaurants
    case showPostOffices, showBanks, showHotels, showHospitals, showCarServices, showParkings, showPolice
    case showSchools, showParks, showSights

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .voiceEnabled: "Голосові підказки"
        case .keepScreenOn: "Екран не гасне під час навігації"
        case .dimEnabled: "Затемнювати екран без дотиків"
        case .motionEnabled: "Датчики руху: стоянка і повороти"
        default: category?.title ?? rawValue
        }
    }

    /// Тип орієнтира, який показує цей фільтр.
    public var category: PlaceCategory? {
        switch self {
        case .voiceEnabled, .keepScreenOn, .dimEnabled, .motionEnabled: nil
        case .showGasStations: .gasStation
        case .showEVChargers: .evCharger
        case .showStores: .store
        case .showFoodMarkets: .foodMarket
        case .showPharmacies: .pharmacy
        case .showCafes: .cafe
        case .showRestaurants: .restaurant
        case .showPostOffices: .postOffice
        case .showBanks: .bank
        case .showHotels: .hotel
        case .showHospitals: .hospital
        case .showCarServices: .carService
        case .showParkings: .parking
        case .showPolice: .police
        case .showSchools: .school
        case .showParks: .park
        case .showSights: .sight
        }
    }

    public var defaultValue: Bool {
        if let category { return category.isShownByDefault }
        return self != .dimEnabled
    }

    public var section: SettingSection {
        switch self {
        case .voiceEnabled: .voice
        case .keepScreenOn, .dimEnabled: .screen
        case .motionEnabled: .sensors
        default: .landmarks
        }
    }

    public static func filter(for category: PlaceCategory) -> SettingToggle {
        // Кожен тип має свій фільтр: це перевіряє тест налаштувань.
        allCases.first { $0.category == category }!
    }
}

/// Усі налаштування однією структурою. Ядро отримує її готовою і не знає, де вона зберігається.
public struct NavigationSettings: Sendable, Equatable {
    private var values: [SettingKey: Double] = [:]
    private var toggles: [SettingToggle: Bool] = [:]

    public init() {}

    public static let standard = NavigationSettings()

    /// Значення завжди в межах `spec.range`: запис поза межами обрізається.
    public subscript(key: SettingKey) -> Double {
        get { values[key] ?? key.spec.defaultValue }
        set { values[key] = key.spec.clamp(newValue) }
    }

    public subscript(toggle: SettingToggle) -> Bool {
        get { toggles[toggle] ?? toggle.defaultValue }
        set { toggles[toggle] = newValue }
    }

    public static func == (lhs: NavigationSettings, rhs: NavigationSettings) -> Bool {
        SettingKey.allCases.allSatisfy { lhs[$0] == rhs[$0] } && SettingToggle.allCases.allSatisfy { lhs[$0] == rhs[$0] }
    }

    public var isStandard: Bool { self == .standard }

    // MARK: Значення в одиницях СІ для логіки

    public var defaultSpeed: Double { self[.defaultSpeedKmh] / 3.6 }
    public var speedStep: Double { self[.speedStepKmh] / 3.6 }
    public var impossibleSpeed: Double { self[.impossibleSpeedKmh] / 3.6 }
    public var courseMinSpeed: Double { self[.courseMinSpeedKmh] / 3.6 }
    public var landmarkSegmentLength: Double { self[.landmarkSegmentKm] * 1000 }

    public var enabledCategories: Set<PlaceCategory> {
        Set(PlaceCategory.allCases.filter { self[SettingToggle.filter(for: $0)] })
    }
}
