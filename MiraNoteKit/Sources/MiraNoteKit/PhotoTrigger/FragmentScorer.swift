import Foundation

// The dimensions keep the spec's one-letter names (R, S, P, N, U, A).
// The scorer takes every input it weighs, plainly.
// swiftlint:disable identifier_name function_parameter_count

/// One photo's position on its belongs-to day, for place novelty (N).
public struct PastLocation: Equatable, Sendable {
    public let id: String
    /// "yyyy-MM-dd", by the 4 am rule.
    public let day: String
    public let point: GeoPoint

    public init(id: String, day: String, point: GeoPoint) {
        self.id = id
        self.day = day
        self.point = point
    }
}

/// A fragment's score: each dimension 0...1, the weighted base and the
/// bucket multiplier.
public struct FragmentScore: Equatable, Sendable, Codable {
    /// Recency, story, people, place novelty, user marks, aesthetics.
    public let r, s, p, n, u, a: Double
    /// The weighted sum of the six dimensions.
    public let base: Double
    /// The bucket's multiplier ("fewer" x0.6 after its block, else 1.0).
    public let multiplier: Double
    public let bucket: PushBucket
    /// `base * multiplier`.
    public let total: Double
    /// Whole days from the fragment's day to the slot's day (both by the 4 am rule).
    public let days: Int
    /// Clears the 0.40 bar.
    public let pushable: Bool
}

/// Ranks fragments (R5b-1 2.5's structure with handoff 7.3's numbers):
/// `total = 0.25 R + 0.20 S + 0.15 P + 0.15 N + 0.15 U + 0.10 A`, every
/// scaled by the bucket multiplier, with recency measured against the push slot.
public enum FragmentScorer {
    public struct Weights: Equatable, Sendable {
        public let recency, story, people, novelty, user, aesthetics: Double
    }

    public static let weights = Weights(recency: 0.25, story: 0.20, people: 0.15, novelty: 0.15,
                                        user: 0.15, aesthetics: 0.10)
    public static let bar = 0.40
    public static let windowDays = 60
    /// A new moment after a pause this long (S's k).
    public static let momentGap: TimeInterval = 20 * 60
    /// The last photo must be at least this long before the slot.
    public static let minimumAge: TimeInterval = 12 * 3600
    static let novelRadiusKm = 0.5

    /// Nil when a hard filter rules the fragment out: under three unique
    /// photos, under 12 h from its last photo to the slot, or more than 60
    /// days from its day to the slot's day. `pastLocations` are the last 90
    /// days' photo positions by belongs-to day; the fragment's own photos
    /// and own day are ignored.
    public static func score(
        _ fragment: Fragment, analyses: [String: PhotoAnalysis], library: [String: LibraryAsset],
        at slot: Date, calendar: Calendar, pastLocations: [PastLocation],
        bucket: PushBucket, multiplier: Double
    ) -> FragmentScore? {
        guard fragment.uniqueCount >= FragmentGrouper.minimumUnique,
              slot.timeIntervalSince(fragment.end) >= minimumAge else { return nil }
        let days = daysBetween(fragment.belongsTo, FragmentGrouper.belongsTo(slot, calendar: calendar))
        guard let days, let r = recency(days: days) else { return nil }

        let unique = fragment.uniquePhotos
        let s = story(fragment)
        let faces = unique.map { analyses[$0.id]?.faces ?? 0 }
        let faceShare = Double(faces.filter { $0 > 0 }.count) / Double(max(1, unique.count))
        let p = 0.6 * min(1, 2 * faceShare) + (faces.contains { $0 >= 2 } ? 0.4 : 0)
        let n = novelty(fragment, pastLocations: pastLocations)
        let marked = fragment.photos.compactMap { library[$0.id] }
        let repeats = fragment.represents.values.contains { $0 >= 3 }
        let u = min(1, (marked.contains(where: \.isFavorite) ? 0.6 : 0)
                    + (marked.contains(where: \.isEdited) ? 0.3 : 0) + (repeats ? 0.3 : 0))
        let a = aesthetics(unique.compactMap { analyses[$0.id]?.aesthetics })

        let total = weights.recency * r + weights.story * s + weights.people * p + weights.novelty * n
            + weights.user * u + weights.aesthetics * a
        let scaled = total * multiplier
        return FragmentScore(r: r, s: s, p: p, n: n, u: u, a: a, base: total, multiplier: multiplier,
                             bucket: bucket, total: scaled, days: days, pushable: scaled >= bar)
    }

    /// The push bucket the fragment's unique photos vote for.
    public static func bucket(of fragment: Fragment, analyses: [String: PhotoAnalysis]) -> PushBucket {
        PushBucket.majority(of: fragment.uniquePhotos.map { analyses[$0.id]?.broad ?? [] })
    }

    /// R by whole days from the fragment's day to the slot's day: up to 10
    /// full, then a straight fall to 0.3 at 60; past 60 (or negative) none.
    public static func recency(days: Int) -> Double? {
        switch days {
        case ..<0: return nil
        case ...10: return 1.0
        case ...windowDays: return 1.0 - 0.7 * Double(days - 10) / Double(windowDays - 10)
        default: return nil
        }
    }

    /// S = 0.4 min(1, k/4) + 0.3 min(1, h/3) + 0.3 min(1, n/10): moments
    /// (unique photos split at 20-minute pauses), hours, unique photos.
    static func story(_ fragment: Fragment) -> Double {
        let times = fragment.uniquePhotos.map(\.takenAt)
        let moments = 1 + zip(times, times.dropFirst()).filter { $1.timeIntervalSince($0) >= momentGap }.count
        let hours = fragment.end.timeIntervalSince(fragment.start) / 3600
        return 0.4 * min(1, Double(moments) / 4) + 0.3 * min(1, hours / 3)
            + 0.3 * min(1, Double(fragment.uniqueCount) / 10)
    }

    /// N by the distinct other days (before or after; decision 11-04) with a
    /// photo within 500 m of the fragment's centre: none 1.0, up to 3 0.7, up to 10 0.4, more 0.1;
    /// no GPS 0.4. The fragment's own photos are never a visit, even those
    /// past 04:00 that fall on the next belongs-to day.
    static func novelty(_ fragment: Fragment, pastLocations: [PastLocation]) -> Double {
        guard let center = fragment.center else { return 0.4 }
        let own = Set(fragment.photos.map(\.id))
        let visits = Set(pastLocations
            .filter { !own.contains($0.id) && $0.day != fragment.belongsTo && $0.point.km(to: center) <= novelRadiusKm }
            .map(\.day)).count
        switch visits {
        case 0: return 1.0
        case ...3: return 0.7
        case ...10: return 0.4
        default: return 0.1
        }
    }

    /// A: the mean of the best three `(x + 1) / 2`; 0.5 without any score.
    static func aesthetics(_ scores: [Double]) -> Double {
        let best = scores.sorted(by: >).prefix(3).map { ($0 + 1) / 2 }
        guard !best.isEmpty else { return 0.5 }
        return best.reduce(0, +) / Double(best.count)
    }

    /// Whole days from one "yyyy-MM-dd" to another.
    static func daysBetween(_ from: String, _ to: String) -> Int? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        func date(_ text: String) -> Date? {
            let parts = text.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        guard let start = date(from), let end = date(to) else { return nil }
        return utc.dateComponents([.day], from: start, to: end).day
    }
}

// swiftlint:enable identifier_name function_parameter_count
