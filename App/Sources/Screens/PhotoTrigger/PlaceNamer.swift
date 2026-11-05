import CoreLocation
import MiraNoteKit

/// The place in a push, from Apple's reverse geocoder in Simplified
/// Chinese whatever the phone's language (handoff 7.3). The coordinate
/// goes to Apple and nowhere else. Nothing found there is no place; any
/// other error (no network, throttled) is thrown, so the night is tried
/// again later rather than composed without its place.
struct PlaceNamer: PlaceNaming {
    func name(for point: GeoPoint) async throws -> String? {
        let location = CLLocation(latitude: point.lat, longitude: point.lon)
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await CLGeocoder().reverseGeocodeLocation(location,
                                                                       preferredLocale: Locale(identifier: "zh-Hans"))
        } catch let error as CLError where error.code == .geocodeFoundNoResult {
            return nil
        }
        guard let placemark = placemarks.first else { return nil }
        return PlaceName.pick(PlaceParts(areasOfInterest: placemark.areasOfInterest ?? [],
                                         subLocality: placemark.subLocality, locality: placemark.locality))
    }
}
