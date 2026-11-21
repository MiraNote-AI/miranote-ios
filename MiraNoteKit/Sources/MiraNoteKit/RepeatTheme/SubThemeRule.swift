import Foundation

/// One occasion a small theme stands for: a time of day, weekday or weekend,
/// and a place (center + 300 m), or no place for photos without a location.
/// `place` is stored with the theme on the phone and never sent anywhere.
public struct OccasionKey: Codable, Equatable, Sendable {
    public let place: GeoPoint?
    /// A `Daypart` raw value.
    public let daypart: String
    /// `weekday` or `weekend`.
    public let weekpart: String

    public init(place: GeoPoint?, daypart: String, weekpart: String) {
        self.place = place
        self.daypart = daypart
        self.weekpart = weekpart
    }
}

/// How a small theme picks its photos from its big theme's list.
public enum SubRule: Codable, Equatable, Sendable {
    /// Any of these Vision labels present.
    case content(evidence: [String])
    /// Any of these occasions.
    case occasion(keys: [OccasionKey])
}

/// Small themes are not claimed: every run their rule is applied again to
/// the big theme's list tonight (spec 6.7).
enum SubThemeRule {
    /// The photos of `photos` (in that order) the rule takes. A photo is
    /// judged by its moment (labels at their best over the burst, the
    /// moment's start and place); one in no moment by its own record; one in
    /// neither is left out.
    ///
    /// Content: an evidence label at or above `PileSplits.presentConfidence`.
    /// Occasion: a key with the same daypart and weekpart whose place is
    /// within `PileSplits.placeKm` of the moment's, or with no place when the
    /// moment has none.
    static func members(_ rule: SubRule, in photos: [String], moments: [String: Moment],
                        photosById: [String: ThemePhoto], calendar: Calendar) -> [String] {
        var momentOf: [String: Moment] = [:]
        for moment in moments.values {
            for photoId in moment.photoIds { momentOf[photoId] = moment }
        }
        return photos.filter { photoId in
            guard let moment = momentOf[photoId] ?? photosById[photoId].map(standalone) else { return false }
            return matches(rule, moment, calendar: calendar)
        }
    }

    /// Tonight's lists of `smallThemes`. A small theme whose big theme froze
    /// (or is not in `claim`) freezes too and keeps its old list; so does one
    /// without a rule. The engine must take small lists from here, never
    /// call `members` for the small themes of a frozen big theme.
    static func membersTonight(of smallThemes: [ThemeRow], claim: ClaimResult, moments: [String: Moment],
                               photosById: [String: ThemePhoto], calendar: Calendar) -> [String: [String]] {
        var lists: [String: [String]] = [:]
        for row in smallThemes where row.kind == .small {
            guard let rule = row.rule, let parent = row.parentId, !claim.frozen.contains(parent),
                  let bigList = claim.members[parent] else {
                lists[row.id] = row.members
                continue
            }
            lists[row.id] = members(rule, in: bigList, moments: moments, photosById: photosById,
                                    calendar: calendar)
        }
        return lists
    }

    private static func matches(_ rule: SubRule, _ moment: Moment, calendar: Calendar) -> Bool {
        switch rule {
        case .content(let evidence):
            let present = Set(moment.labels.filter { $0.confidence >= PileSplits.presentConfidence }.map(\.id))
            return evidence.contains(where: present.contains)
        case .occasion(let keys):
            let daypart = Daypart(hour: calendar.component(.hour, from: moment.start)).rawValue
            let weekpart = PileSplits.weekpart(of: [moment], calendar: calendar)
            return keys.contains { key in
                guard key.daypart == daypart, key.weekpart == weekpart else { return false }
                switch (key.place, moment.location) {
                case (nil, nil): return true
                case let (place?, location?): return place.km(to: location) <= PileSplits.placeKm
                default: return false
                }
            }
        }
    }

    /// A photo outside every moment, as a moment of its own.
    private static func standalone(_ photo: ThemePhoto) -> Moment {
        Moment(id: photo.id, photoIds: [photo.id], day: "", start: photo.takenAt, vector: photo.vector,
               labels: photo.labels, location: photo.location)
    }
}
