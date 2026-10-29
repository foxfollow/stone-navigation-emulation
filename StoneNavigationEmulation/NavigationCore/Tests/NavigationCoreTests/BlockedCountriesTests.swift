import Foundation
import Testing
@testable import NavigationCore

private let blockedTexts = [
    "Москва, Росія",
    "Мінськ, Білорусь",
    "Минск, Беларусь",
    "Санкт-Петербург, Россия, 190000",
    "Moscow, Russia",
    "Brest, Belarus",
    "Москва, Российская Федерация",
    "Гомель · Рэспубліка Беларусь",
    "Росія",
]

private let allowedTexts = [
    "Київ, Україна",
    "вулиця Білоруська, Київ, Україна",
    "Російська вулиця, Харків",
    "Варшава, Польща",
    "",
]

@Suite("Адреси в Росії та Білорусі вимкнено")
@MainActor
struct BlockedCountriesTests {
    @Test("Країна окремою частиною адреси блокується", arguments: blockedTexts)
    func blocksCountryInAddress(text: String) {
        #expect(BlockedCountries.mentioned(in: text))
    }

    @Test("Слово в назві вулиці чи місто в іншій країні не блокується", arguments: allowedTexts)
    func allowsOtherAddresses(text: String) {
        #expect(!BlockedCountries.mentioned(in: text))
    }

    @Test("Коди RU і BY у будь-якому регістрі, інші коди і невідомий код проходять")
    func countryCodes() {
        #expect(BlockedCountries.contains(code: "RU"))
        #expect(BlockedCountries.contains(code: "by"))
        #expect(!BlockedCountries.contains(code: "UA"))
        #expect(!BlockedCountries.contains(code: "PL"))
        #expect(!BlockedCountries.contains(code: nil))
    }

    @Test("Підказки пошуку без Росії та Білорусі")
    func suggestionsAreFiltered() async throws {
        let here = TestRoute.start
        let fake = FakePlaceSearch(places: [
            Place(name: "Червона площа", subtitle: "Москва, Росія", coordinate: here),
            Place(name: "Площа Незалежності", subtitle: "Мінськ, Беларусь", coordinate: here),
            Place(name: "Площа Незалежності", subtitle: "Київ, Україна", coordinate: here),
            Place(name: "Білоруська площа", subtitle: "Київ, Україна", coordinate: here),
        ])
        let search = CountryFilteredPlaceSearch(base: fake)
        let found = try await search.suggestions(for: "площа", near: nil)
        #expect(found.map(\.subtitle) == ["Київ, Україна", "Київ, Україна"])
        #expect(found.map(\.title) == ["Площа Незалежності", "Білоруська площа"])
    }

    @Test("Місце з кодом RU чи BY не можна вибрати, навіть якщо країни немає в підказці")
    func resolveRejectsBlockedCountry() async throws {
        let here = TestRoute.start
        let fake = FakePlaceSearch(places: [
            Place(name: "Вокзал", subtitle: "Гомель", coordinate: here, countryCode: "BY"),
            Place(name: "Вокзал", subtitle: "Бєлгород", coordinate: here, countryCode: "ru"),
            Place(name: "Вокзал", subtitle: "Київ", coordinate: here, countryCode: "UA"),
            Place(name: "Вокзал", subtitle: "Бровари", coordinate: here),
        ])
        let search = CountryFilteredPlaceSearch(base: fake)
        let suggestions = try await search.suggestions(for: "вокзал", near: nil)
        #expect(suggestions.count == 4)
        for suggestion in suggestions.prefix(2) {
            do {
                _ = try await search.resolve(suggestion)
                Issue.record("місце з кодом RU чи BY вибралося: \(suggestion.subtitle)")
            } catch {
                #expect(error as? PlaceSearchError == .blockedCountry)
            }
        }
        let kyiv = try await search.resolve(suggestions[2])
        #expect(kyiv.subtitle == "Київ")
        let brovary = try await search.resolve(suggestions[3])
        #expect(brovary.subtitle == "Бровари")
    }

    @Test("Орієнтири з Росії та Білорусі не потрапляють на маршрут")
    func landmarksSkipBlockedCountries() async {
        let candidates = [
            PlaceCandidate(id: "ua", name: "АЗС Україна", category: .gasStation, coordinate: TestRoute.point(along: 400, offset: 20), countryCode: "UA"),
            PlaceCandidate(id: "by", name: "АЗС Білорусь", category: .gasStation, coordinate: TestRoute.point(along: 500, offset: 20), countryCode: "BY"),
            PlaceCandidate(id: "ru", name: "АЗС Росія", category: .gasStation, coordinate: TestRoute.point(along: 600, offset: 20), countryCode: "RU"),
            PlaceCandidate(id: "unknown", name: "АЗС без коду", category: .gasStation, coordinate: TestRoute.point(along: 700, offset: 20)),
        ]
        let h = SessionHarness(candidates: candidates)
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.gps(TestRoute.point(along: 0))
        h.advance(1)
        await h.session.settle()
        #expect(Set(h.session.landmarks.map(\.id)) == ["ua", "unknown"])
        #expect(Set(h.session.landmarkCandidates.map(\.id)) == ["ua", "unknown"])
    }
}
