import CoreLocation
import MiraNoteKit

/// The place in a push, from Apple's reverse geocoder in Simplified
/// Chinese whatever the phone's language (handoff 7.3). The coordinate
/// goes to Apple and nowhere else; a failure is simply no place.
struct PlaceNamer: PlaceNaming {
    func name(for point: GeoPoint) async -> String? {
        let location = CLLocation(latitude: point.lat, longitude: point.lon)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location,
                                                                        preferredLocale: Locale(identifier: "zh-Hans"))
        guard let placemark = placemarks?.first else { return nil }
        return PlaceName.pick(PlaceParts(areasOfInterest: placemark.areasOfInterest ?? [],
                                         subLocality: placemark.subLocality, locality: placemark.locality))
    }
}
