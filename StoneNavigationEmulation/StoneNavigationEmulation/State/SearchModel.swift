import Foundation
import NavigationCore
import Observation

/// Стан пошуку місця: автодоповнення з паузою після введення.
@MainActor
@Observable
final class SearchModel {
    var query = "" {
        didSet { schedule() }
    }
    private(set) var suggestions: [PlaceSuggestion] = []
    private(set) var isSearching = false
    private(set) var error: String?

    @ObservationIgnored private let places: any PlaceSearch
    @ObservationIgnored private let near: () -> Coordinate?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(places: any PlaceSearch, near: @escaping () -> Coordinate?) {
        self.places = places
        self.near = near
    }

    func resolve(_ suggestion: PlaceSuggestion) async -> Place? {
        do {
            return try await places.resolve(suggestion)
        } catch PlaceSearchError.blockedCountry {
            self.error = BlockedCountries.message
            return nil
        } catch {
            self.error = "Не вдалося знайти місце: \(error.localizedDescription)"
            return nil
        }
    }

    func clear() {
        task?.cancel()
        query = ""
        suggestions = []
        error = nil
    }

    private func schedule() {
        task?.cancel()
        let text = query
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await self.run(text)
        }
    }

    private func run(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            suggestions = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let results = try await places.suggestions(for: text, near: near())
            guard text == query else { return }
            suggestions = results
            error = nil
        } catch {
            self.error = "Пошук недоступний: \(error.localizedDescription)"
        }
    }
}
