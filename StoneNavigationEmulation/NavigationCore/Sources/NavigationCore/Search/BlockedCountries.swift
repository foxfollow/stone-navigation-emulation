import Foundation

/// Адреси в Росії та Білорусі вимкнено: їх немає в підказках пошуку, їх не можна вибрати
/// пунктом призначення чи стартом, і вони не стають орієнтирами.
public enum BlockedCountries {
    /// Коди ISO 3166-1.
    public static let codes: Set<String> = ["RU", "BY"]

    public static let message = "Адреси в Росії та Білорусі вимкнено"

    /// Назви країн українською, російською, білоруською та англійською, як їх пише постачальник у підказках.
    static let names: Set<String> = Set([
        "Росія", "Російська Федерація", "РФ", "Россия", "Российская Федерация",
        "Расія", "Расійская Федэрацыя", "Russia", "Russian Federation",
        "Білорусь", "Білорусія", "Республіка Білорусь", "Беларусь", "Белоруссия",
        "Республика Беларусь", "Рэспубліка Беларусь", "Belarus", "Republic of Belarus",
    ].map(normalize))

    public static func contains(code: String?) -> Bool {
        guard let code else { return false }
        return codes.contains(code.uppercased())
    }

    /// Чи названо в тексті заблоковану країну окремою частиною адреси («Москва, Росія»).
    /// Слово всередині назви («вулиця Білоруська, Київ») не рахується.
    public static func mentioned(in text: String) -> Bool {
        text.components(separatedBy: CharacterSet(charactersIn: ",;·\n"))
            .contains { names.contains(normalize($0)) }
    }

    public static func allows(_ suggestion: PlaceSuggestion) -> Bool {
        !mentioned(in: suggestion.title) && !mentioned(in: suggestion.subtitle)
    }

    /// Без регістру й діакритики, без поштового індексу і зайвих пробілів.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: .decimalDigits).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

/// Пошук місць без адрес у Росії та Білорусі. Обгортає будь-якого постачальника (MapKit, фейк).
@MainActor
public final class CountryFilteredPlaceSearch: PlaceSearch {
    private let base: any PlaceSearch

    public init(base: any PlaceSearch) {
        self.base = base
    }

    public func suggestions(for query: String, near: Coordinate?) async throws -> [PlaceSuggestion] {
        try await base.suggestions(for: query, near: near).filter(BlockedCountries.allows)
    }

    public func resolve(_ suggestion: PlaceSuggestion) async throws -> Place {
        let place = try await base.resolve(suggestion)
        guard !BlockedCountries.contains(code: place.countryCode) else { throw PlaceSearchError.blockedCountry }
        return place
    }

    public func pointsOfInterest(in region: GeoRegion, categories: Set<PlaceCategory>) async throws -> [PlaceCandidate] {
        try await base.pointsOfInterest(in: region, categories: categories)
            .filter { !BlockedCountries.contains(code: $0.countryCode) }
    }
}
