import Foundation
import Testing
@testable import NavigationCore

@Suite("Збережені адреси: дім, робота, вибрані, останні")
struct SavedPlacesTests {
    let maidan = Place(name: "Майдан Незалежності", subtitle: "Київ", coordinate: Coordinate(latitude: 50.4501, longitude: 30.5234))
    let darnytsia = Place(name: "Дарницька площа", subtitle: "Київ", coordinate: Coordinate(latitude: 50.4589, longitude: 30.6295))
    let office = Place(name: "Бізнес-центр", subtitle: "вулиця Хрещатик, 22", coordinate: Coordinate(latitude: 50.4470, longitude: 30.5220))

    func place(_ index: Int) -> Place {
        Place(name: "Місце \(index)", coordinate: Geo.destination(from: maidan.coordinate, bearing: 90, distance: Double(index) * 200))
    }

    @Test("Останні: найновіша перша, без повторів того самого місця, не більше 15")
    func recents() {
        var saved = SavedPlaces()
        saved.store(maidan, as: .recent)
        saved.store(darnytsia, as: .recent)
        // Те саме місце, назва іншою мовою: піднімається нагору, а не дублюється.
        saved.store(Place(name: "Maidan Nezalezhnosti", coordinate: Geo.destination(from: maidan.coordinate, bearing: 0, distance: 10)), as: .recent)
        #expect(saved.recents.map(\.name) == ["Maidan Nezalezhnosti", "Дарницька площа"])
        for index in 1...20 { saved.store(place(index), as: .recent) }
        #expect(saved.recents.count == SavedPlaces.maxRecents)
        #expect(saved.recents.first?.name == "Місце 20")
        #expect(saved.recents.last?.name == "Місце 6")
    }

    @Test("Дім і робота замінюються новою адресою, вибрані без повторів, усе можна прибрати")
    func pinned() throws {
        var saved = SavedPlaces()
        saved.store(darnytsia, as: .home)
        saved.store(maidan, as: .home)
        saved.store(office, as: .work)
        saved.store(darnytsia, as: .favorite)
        saved.store(darnytsia, as: .favorite)
        #expect(saved.home == maidan)
        #expect(saved.pinned.map(\.kind) == [.home, .work, .favorite])
        #expect(saved.pinned.map(\.id) == ["saved.home", "saved.work", "saved.favorite.0"])

        // Останні не повторюють дім, роботу і вибрані.
        saved.store(place(1), as: .recent)
        saved.store(maidan, as: .recent)
        #expect(saved.recentEntries.map(\.place.name) == ["Місце 1"])
        #expect(saved.recentEntries.map(\.id) == ["saved.recent.1"])

        saved.remove(try #require(saved.pinned.first { $0.kind == .home }))
        saved.remove(try #require(saved.pinned.first { $0.kind == .favorite }))
        #expect(saved.home == nil)
        #expect(saved.favorites.isEmpty)
        // Майдан більше не дім, тож знову видно серед останніх.
        #expect(saved.recentEntries.map(\.place.name) == ["Майдан Незалежності", "Місце 1"])
        saved.clearRecents()
        #expect(saved.recentEntries.isEmpty)
    }

    @Test("Пошук: спершу дім, робота і вибрані, потім останні; «дім» знаходить дім")
    func matching() {
        var saved = SavedPlaces()
        saved.store(Place(name: "Майдан Незалежності, 1", coordinate: Geo.destination(from: maidan.coordinate, bearing: 180, distance: 500)), as: .recent)
        saved.store(maidan, as: .home)
        saved.store(office, as: .work)
        #expect(saved.matching("майд").map(\.id) == ["saved.home", "saved.recent.0"])
        #expect(saved.matching("  МАЙДАН ").count == 2)
        #expect(saved.matching("хрещатик").map(\.kind) == [.work])
        #expect(saved.matching("Дім").map(\.kind) == [.home])
        #expect(saved.matching("").isEmpty)
        #expect(saved.matching("Одеса").isEmpty)
    }

    @Test("Адреси в Росії та Білорусі не зберігаються")
    func blockedCountries() {
        var saved = SavedPlaces()
        let moscow = Place(name: "Червона площа", coordinate: Coordinate(latitude: 55.7539, longitude: 37.6208), countryCode: "RU")
        let minsk = Place(name: "Вокзал", coordinate: Coordinate(latitude: 53.89, longitude: 27.55), countryCode: "by")
        let stored = [saved.store(moscow, as: .home), saved.store(minsk, as: .recent), saved.store(moscow, as: .favorite)]
        #expect(stored == [false, false, false])
        #expect(saved == SavedPlaces())
    }

    @Test("Зберігаються між запусками, пошкоджені дані дають порожній список")
    func repository() {
        let storage = InMemoryKeyValueStorage()
        let repository = SavedPlacesRepository(storage: storage)
        var saved = SavedPlaces()
        saved.store(maidan, as: .home)
        saved.store(office, as: .work)
        saved.store(darnytsia, as: .favorite)
        saved.store(place(3), as: .recent)
        repository.save(saved)
        #expect(SavedPlacesRepository(storage: storage).load() == saved)

        storage.set(Data("не JSON".utf8), forKey: SavedPlacesRepository.key)
        #expect(repository.load() == SavedPlaces())
        repository.clear()
        #expect(storage.data(forKey: SavedPlacesRepository.key) == nil)
    }
}
