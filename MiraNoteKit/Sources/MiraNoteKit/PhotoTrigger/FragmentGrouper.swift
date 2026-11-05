import Foundation

/// The little grouping needs to know about a photo.
public struct GroupablePhoto: Equatable, Sendable {
    public let id: String
    public let takenAt: Date
    public let location: GeoPoint?
    public let burstId: String?

    public init(id: String, takenAt: Date, location: GeoPoint?, burstId: String?) {
        self.id = id
        self.takenAt = takenAt
        self.location = location
        self.burstId = burstId
    }
}

/// One life fragment: a candidate group, three or more photos after
/// near-duplicates are counted once.
public struct Fragment: Equatable, Sendable {
    /// Every photo, duplicates included, in time order.
    public let photos: [GroupablePhoto]
    /// Photos after duplicates are counted once ("the count" everywhere).
    public let uniqueCount: Int
    /// Duplicate photo id -> the id of the photo it repeats (its cluster's
    /// first photo, or the first of its burst).
    public let representative: [String: String]
    /// "yyyy-MM-dd": the first photo's day, before 04:00 the day before.
    public let belongsTo: String

    public init(photos: [GroupablePhoto], uniqueCount: Int, representative: [String: String], belongsTo: String) {
        self.photos = photos
        self.uniqueCount = uniqueCount
        self.representative = representative
        self.belongsTo = belongsTo
    }

    public var start: Date { photos.first?.takenAt ?? .distantPast }
    public var end: Date { photos.last?.takenAt ?? .distantPast }

    /// The photos that are not duplicates, in time order.
    public var uniquePhotos: [GroupablePhoto] {
        photos.filter { representative[$0.id] == nil }
    }

    /// How many photos each unique photo stands for (itself included).
    public var represents: [String: Int] {
        var counts = Dictionary(uniqueKeysWithValues: uniquePhotos.map { ($0.id, 1) })
        for anchor in representative.values { counts[anchor, default: 1] += 1 }
        return counts
    }

    /// The average of the photos' GPS points; nil without any.
    public var center: GeoPoint? {
        GeoPoint.center(of: photos.compactMap(\.location))
    }
}

/// Where and why the timeline was cut (step 5), for the debug view.
public struct Cut: Equatable, Sendable {
    public enum Rule: String, Equatable, Sendable {
        /// Rule 2: the gap reached T.
        case timeGap
        /// Rule 3: both have GPS and are more than 10 km apart.
        case distance
    }

    public let after: String
    public let before: String
    public let rule: Rule
    public let gap: TimeInterval
    public let km: Double?
}

public struct GroupingResult: Equatable, Sendable {
    public let fragments: [Fragment]
    public let cuts: [Cut]
    /// Segments left under three unique photos, in time order.
    public let dropped: [[GroupablePhoto]]
    public let threshold: ThresholdResult
}

/// Grouping steps 2-8 of the v1 life-fragment grouping rule: mark duplicates, lay
/// the photos on one timeline (never split by calendar day), cut between
/// neighbours, merge or drop small segments, split anything over a day,
/// and keep what has three or more unique photos.
public enum FragmentGrouper {
    public static let duplicateSeconds: TimeInterval = 120
    public static let duplicateDistance: Float = 0.30
    public static let neverCutBelow: TimeInterval = 20 * 60
    public static let cutKilometres: Double = 10
    public static let mergeKilometres: Double = 1
    public static let mergeGap: TimeInterval = 4 * 3600
    public static let maxSpan: TimeInterval = 24 * 3600
    public static let minimumUnique = 3
    /// Photos before this hour belong to the day before.
    public static let dayStartHour = 4

    public static func group(
        _ photos: [GroupablePhoto], threshold: TimeInterval, calendar: Calendar,
        distance: (String, String) -> Float?
    ) -> GroupingResult {
        group(photos, threshold: ThresholdResult(value: threshold, fallback: nil), calendar: calendar,
              distance: distance)
    }

    /// - Parameter distance: FeaturePrint distance between two photo ids;
    ///   nil when either has none (never a duplicate then).
    public static func group(
        _ photos: [GroupablePhoto], threshold: ThresholdResult, calendar: Calendar,
        distance: (String, String) -> Float?
    ) -> GroupingResult {
        let timeline = photos.sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
        guard !timeline.isEmpty else {
            return GroupingResult(fragments: [], cuts: [], dropped: [], threshold: threshold)
        }
        let duplicates = markDuplicates(timeline, distance: distance)

        // Step 5: cut between neighbours.
        var segments: [[GroupablePhoto]] = [[timeline[0]]]
        var cuts: [Cut] = []
        for (previous, next) in zip(timeline, timeline.dropFirst()) {
            if let cut = cut(between: previous, and: next, threshold: threshold.value) {
                cuts.append(cut)
                segments.append([next])
            } else {
                segments[segments.count - 1].append(next)
            }
        }

        let unique = { (segment: [GroupablePhoto]) in segment.filter { duplicates[$0.id] == nil }.count }
        segments = mergeSmall(segments, unique: unique)
        segments = segments.flatMap(splitLong)

        var fragments: [Fragment] = []
        var dropped: [[GroupablePhoto]] = []
        for segment in segments {
            let count = unique(segment)
            guard count >= minimumUnique else {
                dropped.append(segment)
                continue
            }
            let ids = Set(segment.map(\.id))
            fragments.append(Fragment(
                photos: segment, uniqueCount: count,
                representative: duplicates.filter { ids.contains($0.key) },
                belongsTo: belongsTo(segment[0].takenAt, calendar: calendar)
            ))
        }
        return GroupingResult(fragments: fragments, cuts: cuts, dropped: dropped, threshold: threshold)
    }

    /// Step 2: a photo repeats the current cluster's first photo when it
    /// is of the same burst, or within 120 s and alike. Clusters never
    /// chain: a photo is only ever compared with the first one.
    static func markDuplicates(_ timeline: [GroupablePhoto], distance: (String, String) -> Float?)
        -> [String: String] {
        var duplicates: [String: String] = [:]
        var anchor: GroupablePhoto?
        for photo in timeline {
            if let first = anchor {
                let sameBurst = photo.burstId != nil && photo.burstId == first.burstId
                let alike = photo.takenAt.timeIntervalSince(first.takenAt) <= duplicateSeconds
                    && (distance(first.id, photo.id).map { $0 <= duplicateDistance } ?? false)
                if sameBurst || alike {
                    duplicates[photo.id] = first.id
                    continue
                }
            }
            anchor = photo
        }
        return duplicates
    }

    /// Step 5, first rule that applies: under 20 minutes never cuts; T or
    /// more cuts; both with GPS and over 10 km apart cuts; else no cut.
    static func cut(between previous: GroupablePhoto, and next: GroupablePhoto, threshold: TimeInterval) -> Cut? {
        let gap = next.takenAt.timeIntervalSince(previous.takenAt)
        let km = previous.location.flatMap { here in next.location.map { here.km(to: $0) } }
        if gap < neverCutBelow { return nil }
        if gap >= threshold {
            return Cut(after: previous.id, before: next.id, rule: .timeGap, gap: gap, km: km)
        }
        if let km, km > cutKilometres {
            return Cut(after: previous.id, before: next.id, rule: .distance, gap: gap, km: km)
        }
        return nil
    }

    /// Step 6: a segment under three unique photos joins the neighbour in
    /// the same place (centres within 1 km) less than 4 hours away -- the
    /// nearer in time when both qualify -- until no merge is left. One
    /// without GPS cannot be placed and stays small (then dropped).
    static func mergeSmall(_ input: [[GroupablePhoto]], unique: ([GroupablePhoto]) -> Int) -> [[GroupablePhoto]] {
        var segments = input
        var merged = true
        while merged {
            merged = false
            for index in segments.indices where unique(segments[index]) < minimumUnique {
                guard let here = GeoPoint.center(of: segments[index].compactMap(\.location)) else { continue }
                var best: (neighbour: Int, gap: TimeInterval)?
                for neighbour in [index - 1, index + 1] where segments.indices.contains(neighbour) {
                    guard let there = GeoPoint.center(of: segments[neighbour].compactMap(\.location)),
                          here.km(to: there) <= mergeKilometres else { continue }
                    let gap = neighbour > index
                        ? segments[neighbour][0].takenAt.timeIntervalSince(segments[index].last!.takenAt)
                        : segments[index][0].takenAt.timeIntervalSince(segments[neighbour].last!.takenAt)
                    if gap < mergeGap, best.map({ gap < $0.gap }) ?? true { best = (neighbour, gap) }
                }
                guard let best else { continue }
                let low = min(index, best.neighbour)
                segments[low] = (segments[low] + segments[low + 1]).sorted { $0.takenAt < $1.takenAt }
                segments.remove(at: low + 1)
                merged = true
                break
            }
        }
        return segments
    }

    /// Step 7: over 24 hours from first to last, cut at the longest gap,
    /// again until every piece fits in a day.
    static func splitLong(_ segment: [GroupablePhoto]) -> [[GroupablePhoto]] {
        guard segment.count > 1,
              segment[segment.count - 1].takenAt.timeIntervalSince(segment[0].takenAt) > maxSpan
        else { return [segment] }
        let gaps = zip(segment, segment.dropFirst()).map { $1.takenAt.timeIntervalSince($0.takenAt) }
        let longest = gaps.indices.max { gaps[$0] < gaps[$1] } ?? 0
        return splitLong(Array(segment[...longest])) + splitLong(Array(segment[(longest + 1)...]))
    }

    /// Step 8's day: the date of `date` in `calendar`, with the small hours
    /// (before 04:00) counted as the day before. The hour is the wall
    /// clock's, so a daylight-saving change does not move the boundary.
    public static func belongsTo(_ date: Date, calendar: Calendar) -> String {
        let small = calendar.component(.hour, from: date) < dayStartHour
        let day = small ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
