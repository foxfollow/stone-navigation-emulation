import Foundation
import Testing
@testable import NavigationCore

@Suite("Налаштування: межі та збереження")
struct SettingsTests {
    @Test("Стандартні значення та межі відповідають специфікації", arguments: [
        (SettingKey.defaultSpeedKmh, 50.0, 10.0...130.0),
        (.speedStepKmh, 5, 1...20),
        (.shiftStepMeters, 50, 10...500),
        (.updateInterval, 1, 0.5...5),
        (.enterAccuracy, 100, 30...500),
        (.staleAge, 3, 1...30),
        (.returnAccuracy, 30, 5...100),
        (.returnDuration, 5, 1...30),
        (.spoofDistance, 500, 100...5000),
        (.impossibleSpeedKmh, 200, 120...400),
        (.offRouteThreshold, 50, 20...300),
        (.voiceFarDistance, 300, 50...2000),
        (.voiceNearDistance, 100, 50...2000),
        (.landmarkSegmentKm, 10, 2...50),
        // Коридор: 50 м і межі 10–2000 за коментарем до макета.
        (.landmarkCorridor, 50, 10...2000),
        (.dimAfter, 30, 10...300),
    ])
    func specDefaults(key: SettingKey, value: Double, range: ClosedRange<Double>) {
        #expect(NavigationSettings.standard[key] == value)
        #expect(key.spec.range == range)
    }

    @Test("Перемикачі за замовчуванням: голос і «екран не гасне» увімкнені, затемнення вимкнене")
    func toggleDefaults() {
        let settings = NavigationSettings.standard
        #expect(settings[.voiceEnabled])
        #expect(settings[.keepScreenOn])
        #expect(!settings[.dimEnabled])
        // Орієнтири: помітні з дороги типи увімкнені, решту водій вмикає сам.
        #expect(settings.enabledCategories == [.gasStation, .store, .foodMarket, .pharmacy, .cafe, .restaurant, .postOffice])
    }

    @Test("Кожен тип орієнтира має свій фільтр")
    func categoryFilters() {
        let filters = PlaceCategory.allCases.map(SettingToggle.filter(for:))
        #expect(Set(filters).count == PlaceCategory.allCases.count)
        for category in PlaceCategory.allCases {
            let filter = SettingToggle.filter(for: category)
            #expect(filter.category == category)
            #expect(filter.section == .landmarks)
            #expect(filter.title == category.title)
        }
        #expect(SettingToggle.voiceEnabled.category == nil)
    }

    @Test("Кожне налаштування має коректні межі, крок і стандарт усередині меж")
    func everySpecIsSane() {
        for key in SettingKey.allCases {
            let spec = key.spec
            #expect(spec.range.contains(spec.defaultValue), "\(key)")
            #expect(spec.step > 0, "\(key)")
            #expect(!spec.title.isEmpty && !spec.unit.isEmpty, "\(key)")
        }
    }

    @Test("Значення поза межами обрізаються", arguments: SettingKey.allCases)
    func clamping(key: SettingKey) {
        var settings = NavigationSettings()
        settings[key] = key.spec.range.upperBound * 10 + 1
        #expect(settings[key] == key.spec.range.upperBound)
        settings[key] = key.spec.range.lowerBound - 1000
        #expect(settings[key] == key.spec.range.lowerBound)
        settings[key] = .nan
        #expect(settings[key] == key.spec.defaultValue)
    }

    @Test("Збереження і читання через репозиторій дають ті самі значення")
    func persistenceRoundTrip() {
        let storage = InMemoryKeyValueStorage()
        var settings = NavigationSettings()
        settings[.defaultSpeedKmh] = 70
        settings[.enterAccuracy] = 60
        settings[.landmarkCorridor] = 120
        settings[.voiceEnabled] = false
        settings[.dimEnabled] = true
        settings[.showStores] = false
        SettingsRepository(storage: storage).save(settings)

        // Новий репозиторій на тому самому сховищі, як після перезапуску.
        let loaded = SettingsRepository(storage: storage).load()
        #expect(loaded == settings)
        #expect(loaded[.defaultSpeedKmh] == 70)
        #expect(!loaded[.voiceEnabled])
        #expect(loaded.enabledCategories == [.gasStation, .foodMarket, .pharmacy, .cafe, .restaurant, .postOffice])
    }

    @Test("Пошкоджені значення у сховищі обрізаються при читанні")
    func clampsOnLoad() {
        let storage = InMemoryKeyValueStorage()
        storage.set(9999, forKey: SettingsRepository.prefix + SettingKey.defaultSpeedKmh.rawValue)
        storage.set(1, forKey: SettingsRepository.prefix + SettingKey.spoofDistance.rawValue)
        let loaded = SettingsRepository(storage: storage).load()
        #expect(loaded[.defaultSpeedKmh] == 130)
        #expect(loaded[.spoofDistance] == 100)
    }

    @Test("Скинути до стандартних прибирає збережене")
    func reset() {
        let storage = InMemoryKeyValueStorage()
        let repository = SettingsRepository(storage: storage)
        var settings = NavigationSettings()
        settings[.staleAge] = 20
        settings[.keepScreenOn] = false
        repository.save(settings)
        #expect(repository.reset() == .standard)
        #expect(repository.load() == .standard)
        #expect(repository.load().isStandard)
    }

    @Test("Значення в одиницях СІ для логіки")
    func siConversions() {
        let settings = NavigationSettings.standard
        #expect(abs(settings.defaultSpeed - 13.888) < 0.01)
        #expect(abs(settings.impossibleSpeed - 55.555) < 0.01)
        #expect(settings.landmarkSegmentLength == 10_000)
    }
}
