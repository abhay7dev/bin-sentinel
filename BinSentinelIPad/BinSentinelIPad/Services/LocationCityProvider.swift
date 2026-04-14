import Combine
import CoreLocation
import Foundation

/// Requests one-shot location and maps it to the nearest supported MRF `City`.
final class LocationCityProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var resolvedCity: City?
    @Published private(set) var statusMessage: String = "Finding nearest MRF…"

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func start() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            applyFallback(reason: "Location access off — using Seattle MRF. Enable in Settings to auto-pick by location.")
        @unknown default:
            applyFallback(reason: "Location unavailable — using Seattle MRF.")
        }
    }

    private func applyFallback(reason: String) {
        resolvedCity = .seattle
        statusMessage = reason
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            applyFallback(reason: "Location denied — using Seattle MRF. Enable location to auto-pick nearest city.")
        case .notDetermined:
            break
        @unknown default:
            applyFallback(reason: "Location unavailable — using Seattle MRF.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let city = CityGeo.closestCity(to: location.coordinate)
        DispatchQueue.main.async {
            self.resolvedCity = city
            self.statusMessage = "Nearest MRF: \(city.displayName)"
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.resolvedCity = .seattle
            self.statusMessage = "Could not get location — using Seattle MRF."
        }
    }
}
