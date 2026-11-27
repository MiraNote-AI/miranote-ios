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
    /// Any of these Vision labels present; a row with a center also takes
    /// only the photos that look like it (`SubThemeRule.lists`).
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
        let judged = judge(photos, moments: moments, photosById: photosById)
        return judged.filter { matches(rule, $0.moment, calendar: calendar) }.map(\.photoId)
    }

    /// Tonight's lists of the small rows among `rows`, made by `lists` per
    /// big row. A small theme whose big theme froze (or is not in `claim`,
    /// or not among `rows`) freezes too and keeps its old list. The engine
    /// must take small lists from here, never call `members` for the small
    /// themes of a frozen big theme.
    static func membersTonight(of rows: [ThemeRow], claim: ClaimResult, moments: [String: Moment],
                               photosById: [String: ThemePhoto], calendar: Calendar) -> [String: [String]] {
        let smalls = rows.filter { $0.kind == .small }
        var lists = Dictionary(smalls.map { ($0.id, $0.members) }, uniquingKeysWith: { first, _ in first })
        for parent in rows where parent.kind == .big && !claim.frozen.contains(parent.id) {
            guard let bigList = claim.members[parent.id] else { continue }
            let children = smalls.filter { $0.parentId == parent.id }
            guard !children.isEmpty else { continue }
            lists.merge(self.lists(children: children, parent: parent, in: bigList, moments: moments,
                                   photosById: photosById, calendar: calendar)) { _, new in new }
        }
        return lists
    }

    // swiftlint:disable function_parameter_count
    /// The lists of `children` (small rows of `parent`) within `bigList`,
    /// each in `bigList` order (decision 2):
    /// - an occasion child, or a content child without a center (an old
    ///   row), takes what `members` gives its rule;
    /// - content children with a center share the photos: a photo's moment
    ///   goes to the child whose center is nearest its look (tie: the first
    ///   child), only when that is strictly nearer than `parent.center`
    ///   (skipped when the parent has none) and the moment holds one of that
    ///   child's evidence labels at `PileSplits.presentConfidence`. A moment
    ///   whose look has no length in common with the centers joins none;
    /// - a retired child, or one without a rule, keeps its old list and
    ///   takes part in nothing.
    static func lists(children: [ThemeRow], parent: ThemeRow, in bigList: [String], moments: [String: Moment],
                      photosById: [String: ThemePhoto], calendar: Calendar) -> [String: [String]] {
        let judged = judge(bigList, moments: moments, photosById: photosById)
        var lists: [String: [String]] = [:]
        var byLook: [LookChild] = []
        for child in children {
            guard child.status != .retired, let rule = child.rule else {
                lists[child.id] = child.members
                continue
            }
            if case .content(let evidence) = rule, let center = child.center, !center.isEmpty {
                byLook.append(LookChild(id: child.id, center: center, evidence: evidence))
                lists[child.id] = []
            } else {
                lists[child.id] = judged.filter { matches(rule, $0.moment, calendar: calendar) }.map(\.photoId)
            }
        }
        guard !byLook.isEmpty else { return lists }
        let parentCenter = parent.center ?? []
        for (photoId, moment) in judged {
            var nearest: (index: Int, distance: Float)?
            for (index, child) in byLook.enumerated() where child.center.count == moment.vector.count {
                let distance = MomentBuilder.cosineDistance(moment.vector, child.center)
                if nearest.map({ distance < $0.distance }) ?? true { nearest = (index, distance) }
            }
            guard let nearest else { continue }
            if !parentCenter.isEmpty,
               nearest.distance >= MomentBuilder.cosineDistance(moment.vector, parentCenter) { continue }
            let child = byLook[nearest.index]
            guard matches(.content(evidence: child.evidence), moment, calendar: calendar) else { continue }
            lists[child.id, default: []].append(photoId)
        }
        return lists
    }

    // swiftlint:enable function_parameter_count

    /// A content child that takes photos by look.
    private struct LookChild {
        let id: String
        let center: [Float]
        let evidence: [String]
    }

    /// Each photo of `photos` (in that order) with the moment it is judged
    /// by: its moment, else its own record as one; a photo in neither is
    /// left out.
    private static func judge(_ photos: [String], moments: [String: Moment],
                              photosById: [String: ThemePhoto]) -> [(photoId: String, moment: Moment)] {
        var momentOf: [String: Moment] = [:]
        for moment in moments.values {
            for photoId in moment.photoIds { momentOf[photoId] = moment }
        }
        return photos.compactMap { photoId in
            (momentOf[photoId] ?? photosById[photoId].map(standalone)).map { (photoId, $0) }
        }
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
