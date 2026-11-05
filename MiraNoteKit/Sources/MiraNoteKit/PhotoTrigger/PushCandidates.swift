import Foundation

/// Why a group may not be pushed in a slot, in the order the rules check.
public enum Ineligible: String, Codable, Sendable, Error {
    case tooFewPhotos, tooRecent, tooOld, lowScore, pushedDay, blockedDay, bucketCooldown, aiRejected
}

/// A group that passed every rule for one slot.
public struct PushCandidate: Equatable, Sendable {
    public let fragment: Fragment
    public let groupKey: String
    /// The fragment's belongs-to day.
    public let belongsTo: String
    public let bucket: PushBucket
    public let score: FragmentScore
    /// The preselected photos the AI would see.
    public let aiPhotoIds: [String]
    /// `AIResultCache.key(aiPhotoIds)`.
    public let cacheKey: String
}

/// Which groups may go out in a slot, best first.
public enum PushCandidates {
    // swiftlint:disable function_parameter_count

    /// Runs the rules in order: too few photos, too recent (under 12 h to the
    /// slot), too old (over 60 days), day already pushed, day blocked, bucket
    /// cooling down, score under the bar, cached AI refusal.
    public static func evaluate(
        _ fragment: Fragment, bucket: PushBucket, aiPhotoIds: [String], at slot: Date,
        analyses: [String: PhotoAnalysis], library: [String: LibraryAsset], calendar: Calendar,
        pastLocations: [PastLocation], pushedDays: Set<String>,
        preferences: PushPreferences, cache: (String) -> AIVerdict?
    ) -> Result<PushCandidate, Ineligible> {
        if fragment.uniqueCount < FragmentGrouper.minimumUnique { return .failure(.tooFewPhotos) }
        if slot.timeIntervalSince(fragment.end) < FragmentScorer.minimumAge { return .failure(.tooRecent) }
        let days = FragmentScorer.daysBetween(fragment.belongsTo, FragmentGrouper.belongsTo(slot, calendar: calendar))
        guard let days, days >= 0 else { return .failure(.tooRecent) }
        if days > FragmentScorer.windowDays { return .failure(.tooOld) }
        if pushedDays.contains(fragment.belongsTo) { return .failure(.pushedDay) }
        if preferences.isBlocked(fragment.belongsTo) { return .failure(.blockedDay) }
        guard let multiplier = preferences.multiplier(for: bucket, at: slot) else {
            return .failure(.bucketCooldown)
        }
        guard let score = FragmentScorer.score(
            fragment, analyses: analyses, library: library, at: slot, calendar: calendar,
            pastLocations: pastLocations, bucket: bucket, multiplier: multiplier
        ), score.pushable else { return .failure(.lowScore) }
        let key = AIResultCache.key(aiPhotoIds)
        if case .rejected = cache(key) { return .failure(.aiRejected) }
        return .success(PushCandidate(fragment: fragment, groupKey: ComposeMeta.groupKey(fragment),
                                      belongsTo: fragment.belongsTo, bucket: bucket, score: score,
                                      aiPhotoIds: aiPhotoIds, cacheKey: key))
    }

    /// Every eligible fragment for the slot, best total first; ties go to the
    /// earlier belongs-to day, then the group key. `aiPhotoIds` gives each
    /// fragment's preselected photos.
    public static func ranked(
        _ fragments: [Fragment], aiPhotoIds: (Fragment) -> [String], at slot: Date,
        analyses: [String: PhotoAnalysis], library: [String: LibraryAsset], calendar: Calendar,
        pastLocations: [PastLocation], pushedDays: Set<String>,
        preferences: PushPreferences, cache: (String) -> AIVerdict?
    ) -> [PushCandidate] {
        fragments.compactMap { fragment -> PushCandidate? in
            let bucket = FragmentScorer.bucket(of: fragment, analyses: analyses)
            let result = evaluate(
                fragment, bucket: bucket, aiPhotoIds: aiPhotoIds(fragment), at: slot, analyses: analyses,
                library: library, calendar: calendar, pastLocations: pastLocations, pushedDays: pushedDays,
                preferences: preferences, cache: cache)
            return try? result.get()
        }
        .sorted(by: isRankedBefore)
    }
    // swiftlint:enable function_parameter_count

    /// `ranked`'s order: best total first; ties go to the earlier belongs-to
    /// day, then the group key.
    static func isRankedBefore(_ first: PushCandidate, _ second: PushCandidate) -> Bool {
        if first.score.total != second.score.total { return first.score.total > second.score.total }
        if first.belongsTo != second.belongsTo { return first.belongsTo < second.belongsTo }
        return first.groupKey < second.groupKey
    }
}
