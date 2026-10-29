import CoreLocation
import NavigationCore

/// Справжня геолокація: CLLocationManager з навігаційною точністю, фоном і дозволом «Завжди».
@MainActor
final class CoreLocationSource: NSObject, LocationSource, CLLocationManagerDelegate {
    var onEvent: (@MainActor (LocationEvent) -> Void)?

    private let manager = CLLocationManager()
    private var wantsUpdates = false
    private var isUpdating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        wantsUpdates = true
        handleAuthorization()
    }

    func stop() {
        wantsUpdates = false
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    private func handleAuthorization() {
        guard wantsUpdates else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Після «Під час використання» iOS пропонує підвищити до «Завжди».
            manager.requestAlwaysAuthorization()
            beginUpdates()
        case .authorizedAlways:
            beginUpdates()
        case .denied, .restricted:
            onEvent?(.error(.denied))
        @unknown default:
            beginUpdates()
        }
    }

    private func beginUpdates() {
        guard !isUpdating else { return }
        isUpdating = true
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { handleAuthorization() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map(LocationFix.init)
        MainActor.assumeIsolated {
            for fix in fixes { onEvent?(.fix(fix)) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let kind: LocationErrorKind
        switch (error as? CLError)?.code {
        case .locationUnknown?: kind = .locationUnknown
        case .denied?: kind = .denied
        case .network?: kind = .network
        default: kind = .other
        }
        MainActor.assumeIsolated { onEvent?(.error(kind)) }
    }
}
