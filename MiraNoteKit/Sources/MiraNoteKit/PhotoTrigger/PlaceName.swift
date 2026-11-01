import Foundation

/// What Apple's reverse geocoder said about a fragment's centre, in
/// Simplified Chinese.
public struct PlaceParts: Equatable, Sendable {
    public let areasOfInterest: [String]
    public let subLocality: String?
    public let locality: String?

    public init(areasOfInterest: [String], subLocality: String?, locality: String?) {
        self.areasOfInterest = areasOfInterest
        self.subLocality = subLocality
        self.locality = locality
    }
}

/// The place in a push (handoff 7.3, acceptance D5): a sight or area
/// first, then the district, then the city; nothing when none is known.
public enum PlaceName {
    public static func pick(_ parts: PlaceParts) -> String? {
        let candidates = [parts.areasOfInterest.first, parts.subLocality, parts.locality]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }
}
