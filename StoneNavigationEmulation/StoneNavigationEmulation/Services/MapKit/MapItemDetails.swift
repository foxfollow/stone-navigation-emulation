import MapKit
import NavigationCore

/// MKMapItem для системної картки місця («Детальніше»): там є графік роботи, якого не віддає API.
@MainActor
enum MapItemDetails {
    static func mapItem(for place: PlaceCandidate) async -> MKMapItem {
        if let raw = place.mapItemIdentifier, let identifier = MKMapItem.Identifier(rawValue: raw) {
            let request = MKMapItemRequest(mapItemIdentifier: identifier)
            if let item = try? await request.mapItem {
                return item
            }
        }
        // Без ідентифікатора або без мережі: картка з назвою і точкою.
        let item = MKMapItem(location: place.coordinate.clLocation, address: nil)
        item.name = place.name
        item.pointOfInterestCategory = MapKitConversions.mapKitCategories(place.category).first
        return item
    }
}
