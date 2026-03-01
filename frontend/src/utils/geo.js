/**
 * Approximate city-center coordinates for supported MRF cities.
 * Used to pick the closest city to the user's location.
 */
export const CITY_COORDINATES = {
  seattle: { lat: 47.6062, lng: -122.3321 },
  nyc: { lat: 40.7128, lng: -74.006 },
  la: { lat: 34.0522, lng: -118.2437 },
  chicago: { lat: 41.8781, lng: -87.6298 },
};

/**
 * Haversine distance in kilometers between two lat/lng points.
 */
function haversineDistance(lat1, lng1, lat2, lng2) {
  const R = 6371; // Earth radius in km
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Returns the supported city key ("seattle" | "nyc" | "la" | "chicago")
 * that is closest to the given coordinates.
 */
export function getClosestCity(lat, lng) {
  let closest = "seattle";
  let minDist = Infinity;

  for (const [city, coords] of Object.entries(CITY_COORDINATES)) {
    const dist = haversineDistance(lat, lng, coords.lat, coords.lng);
    if (dist < minDist) {
      minDist = dist;
      closest = city;
    }
  }

  return closest;
}
