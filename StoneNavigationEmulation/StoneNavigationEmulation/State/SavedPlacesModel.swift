import Foundation
import NavigationCore
import Observation

/// Дім, робота, вибрані й останні адреси для пошуку. Зберігаються між запусками.
@MainActor
@Observable
final class SavedPlacesModel {
    private(set) var places: SavedPlaces

    @ObservationIgnored private let repository: SavedPlacesRepository

    init(repository: SavedPlacesRepository) {
        self.repository = repository
        self.places = repository.load()
    }

    @discardableResult
    func store(_ place: Place, as kind: SavedPlaces.Kind) -> Bool {
        var updated = places
        guard updated.store(place, as: kind) else { return false }
        commit(updated)
        return true
    }

    func remove(_ entry: SavedPlaces.Entry) {
        var updated = places
        updated.remove(entry)
        commit(updated)
    }

    func clearRecents() {
        var updated = places
        updated.clearRecents()
        commit(updated)
    }

    private func commit(_ updated: SavedPlaces) {
        places = updated
        repository.save(updated)
    }
}
