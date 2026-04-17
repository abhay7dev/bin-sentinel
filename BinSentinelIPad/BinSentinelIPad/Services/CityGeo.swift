import CoreLocation
import Foundation

/// Approximate city-center coordinates for supported MRF cities (matches web `geo.js`).
enum CityGeo {
    private static let coordinates: [City: CLLocationCoordinate2D] = [
        .seattle: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
        .nyc: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        .la: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),
        .chicago: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
    ]

    /// Haversine distance in kilometers.
    private static func distanceKm(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let r = 6371.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h =
            sin(dLat / 2) * sin(dLat / 2)
                + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(h), sqrt(1 - h))
    }

    static func closestCity(to coordinate: CLLocationCoordinate2D) -> City {
        var best: City = .seattle
        var minKm = Double.greatestFiniteMagnitude
        for (city, coord) in coordinates {
            let d = distanceKm(from: coordinate, to: coord)
            if d < minKm {
                minKm = d
                best = city
            }
        }
        return best
    }
}
