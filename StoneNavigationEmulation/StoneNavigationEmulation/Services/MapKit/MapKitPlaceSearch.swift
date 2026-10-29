import MapKit
import NavigationCore

/// Пошук на MapKit: автодоповнення MKLocalSearchCompleter, місце через MKLocalSearch,
/// орієнтири через MKLocalPointsOfInterestRequest з MKPointOfInterestFilter.
@MainActor
final class MapKitPlaceSearch: NSObject, PlaceSearch, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var pending: CheckedContinuation<[PlaceSuggestion], Never>?
    private var completions: [String: MKLocalSearchCompletion] = [:]

    /// Радіус пріоритету підказок навколо поточної позиції.
    static let suggestionRadius: CLLocationDistance = 50_000
    static let maxSuggestions = 15

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func suggestions(for query: String, near: Coordinate?) async throws -> [PlaceSuggestion] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        if let near {
            completer.region = MKCoordinateRegion(center: near.cl, latitudinalMeters: Self.suggestionRadius, longitudinalMeters: Self.suggestionRadius)
        }
        pending?.resume(returning: [])
        pending = nil
        return await withCheckedContinuation { continuation in
            pending = continuation
            completer.queryFragment = text
        }
    }

    func resolve(_ suggestion: PlaceSuggestion) async throws -> Place {
        guard let completion = completions[suggestion.id] else { throw PlaceSearchError.notFound }
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        return try await withCheckedThrowingContinuation { continuation in
            search.start { response, error in
                if let error {
                    continuation.resume(throwing: MapKitConversions.placeError(error))
                } else if let item = response?.mapItems.first {
                    continuation.resume(returning: MapKitConversions.place(item))
                } else {
                    continuation.resume(throwing: PlaceSearchError.notFound)
                }
            }
        }
    }

    func pointsOfInterest(in region: GeoRegion, categories: Set<PlaceCategory>) async throws -> [PlaceCandidate] {
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region.mkRegion)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories.flatMap(MapKitConversions.mapKitCategories))
        let search = MKLocalSearch(request: request)
        return try await withCheckedThrowingContinuation { continuation in
            search.start { response, error in
                if let error {
                    continuation.resume(throwing: MapKitConversions.placeError(error))
                } else {
                    continuation.resume(returning: (response?.mapItems ?? []).compactMap(MapKitConversions.candidate))
                }
            }
        }
    }

    // MARK: MKLocalSearchCompleterDelegate (викликається на головному потоці)

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { deliver(self.completer.results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated { deliver([]) }
    }

    private func deliver(_ results: [MKLocalSearchCompletion]) {
        completions.removeAll()
        var suggestions: [PlaceSuggestion] = []
        for (index, completion) in results.prefix(Self.maxSuggestions).enumerated() {
            let id = "\(index)|\(completion.title)|\(completion.subtitle)"
            completions[id] = completion
            suggestions.append(PlaceSuggestion(id: id, title: completion.title, subtitle: completion.subtitle))
        }
        pending?.resume(returning: suggestions)
        pending = nil
    }
}
