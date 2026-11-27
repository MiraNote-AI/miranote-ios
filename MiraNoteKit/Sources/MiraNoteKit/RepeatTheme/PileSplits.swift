import Foundation

/// One candidate sub-theme of a pile.
public struct SplitGroup: Codable, Equatable, Sendable {
    /// `A1`... for the by-content split, `B1`... for the by-time-and-place split.
    public let id: String
    /// A label id, or `placeIndex|daypart|weekpart` (`unknown` without a place).
    public let key: String
    /// Member moment ids, by moment start.
    public let momentIds: [String]
    /// How many different days the members fall on.
    public let days: Int
    public let `where`: WhereFacts
    /// The place's center (B groups with a place only). Stays on the phone.
    public let placeCenter: GeoPoint?

    public init(id: String, key: String, momentIds: [String], days: Int, where: WhereFacts,
                placeCenter: GeoPoint?) {
        self.id = id
        self.key = key
        self.momentIds = momentIds
        self.days = days
        self.where = `where`
        self.placeCenter = placeCenter
    }
}

/// The two candidate ways to cut one pile into sub-themes (spec S5).
enum PileSplits {
    /// A label is present at or above this confidence.
    static let presentConfidence: Float = 0.3
    /// Split A drops labels present in more than this share of the pile.
    static let commonShare = 0.6
    /// Moments this close (km) to a place's center belong to it.
    static let placeKm = 0.3
    /// Groups with fewer days are dropped (their moments become A0 / B0).
    static let minDays = 3
    static let maxGroups = 6
    /// Share of moments at which a pile counts as weekday or weekend.
    static let weekpartShare = 0.7

    static func make(_ pile: Pile, moments: [String: Moment],
                     calendar: Calendar) -> (a: [SplitGroup], b: [SplitGroup]) {
        let members = pile.momentIds.compactMap { moments[$0] }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        guard !members.isEmpty else { return ([], []) }
        let places = assignPlaces(members)
        return (splitA(members, places: places, calendar: calendar),
                splitB(members, places: places, calendar: calendar))
    }

    // MARK: - Label shares

    /// How one label is spread inside a group and in the rest of its pile.
    struct TagShare: Equatable, Sendable {
        let label: String
        let inside: Double
        let outside: Double
    }

    /// At most this many shares per group.
    static let maxTagShares = 8

    /// Labels present in at least one moment of the group, with the share of
    /// the group's moments and of the pile's other moments that hold them.
    /// Sorted by sharp first, then inside (high first), then label; the first
    /// eight are kept, so a sharp label is never cut by generic ones.
    static func tagShares(of groupMomentIds: [String], pile: Pile, moments: [String: Moment]) -> [TagShare] {
        func present(_ moment: Moment) -> Set<String> {
            Set(moment.labels.filter { $0.confidence >= presentConfidence }.map(\.id))
        }
        let inGroup = Set(groupMomentIds)
        let inside = groupMomentIds.compactMap { moments[$0] }.map(present)
        let others = pile.momentIds.filter { !inGroup.contains($0) }.compactMap { moments[$0] }.map(present)
        var counts: [String: Int] = [:]
        for labels in inside { for label in labels { counts[label, default: 0] += 1 } }
        let shares = counts.map { label, count -> TagShare in
            let outsideCount = others.filter { $0.contains(label) }.count
            return TagShare(label: label, inside: Double(count) / Double(inside.count),
                            outside: others.isEmpty ? 0 : Double(outsideCount) / Double(others.count))
        }
        return Array(shares.sorted { first, second in
            let firstSharp = isSharp(first), secondSharp = isSharp(second)
            if firstSharp != secondSharp { return firstSharp }
            return first.inside != second.inside ? first.inside > second.inside : first.label < second.label
        }.prefix(maxTagShares))
    }

    /// A label that marks the group: in at least 30% of it, and at most half
    /// as common outside it.
    static func isSharp(_ share: TagShare) -> Bool {
        share.inside >= 0.3 && share.outside <= share.inside / 2
    }

    // MARK: - Split A

    private static func splitA(_ members: [Moment], places: Places, calendar: Calendar) -> [SplitGroup] {
        var presentIn: [String: Int] = [:]
        for moment in members {
            for id in Set(moment.labels.filter { $0.confidence >= presentConfidence }.map(\.id)) {
                presentIn[id, default: 0] += 1
            }
        }
        let common = Set(presentIn.filter { Double($0.value) / Double(members.count) > commonShare }.keys)

        var byLabel: [String: [Moment]] = [:]
        for moment in members {
            let best = moment.labels
                .filter { $0.confidence >= presentConfidence && !common.contains($0.id) }
                .min { $0.confidence != $1.confidence ? $0.confidence > $1.confidence : $0.id < $1.id }
            if let best { byLabel[best.id, default: []].append(moment) }
        }
        return groups(byLabel, prefix: "A", places: places, calendar: calendar, center: { _ in nil })
    }

    // MARK: - Split B

    private static func splitB(_ members: [Moment], places: Places, calendar: Calendar) -> [SplitGroup] {
        var byKey: [String: [Moment]] = [:]
        for moment in members {
            let hour = calendar.component(.hour, from: moment.start)
            let place = places.index[moment.id].map(String.init) ?? "unknown"
            let key = "\(place)|\(Daypart(hour: hour).rawValue)|\(weekpart(of: [moment], calendar: calendar))"
            byKey[key, default: []].append(moment)
        }
        return groups(byKey, prefix: "B", places: places, calendar: calendar) { moments in
            moments.lazy.compactMap { places.index[$0.id] }.first.map { places.centers[$0] }
        }
    }

    // MARK: - Shared

    /// Drops small groups, ranks (days, moments, key), keeps six, numbers them.
    private static func groups(_ buckets: [String: [Moment]], prefix: String, places: Places,
                               calendar: Calendar, center: ([Moment]) -> GeoPoint?) -> [SplitGroup] {
        let ranked = buckets.compactMap { key, moments -> Ranked? in
            let days = Set(moments.map(\.day)).count
            return days >= minDays ? Ranked(key: key, moments: moments, days: days) : nil
        }
        .sorted { first, second in
            if first.days != second.days { return first.days > second.days }
            if first.moments.count != second.moments.count { return first.moments.count > second.moments.count }
            return first.key < second.key
        }
        return ranked.prefix(maxGroups).enumerated().map { offset, entry in
            SplitGroup(id: "\(prefix)\(offset + 1)", key: entry.key, momentIds: entry.moments.map(\.id),
                       days: entry.days, where: facts(entry.moments, places: places, calendar: calendar),
                       placeCenter: center(entry.moments))
        }
    }

    private static func facts(_ moments: [Moment], places: Places, calendar: Calendar) -> WhereFacts {
        let hours = moments.map { calendar.component(.hour, from: $0.start) }.sorted()
        var perDaypart: [Daypart: Int] = [:]
        for hour in hours { perDaypart[Daypart(hour: hour), default: 0] += 1 }
        let dominant = Daypart.allCases.filter { perDaypart[$0] != nil }
            .max { (perDaypart[$0] ?? 0) < (perDaypart[$1] ?? 0) }
        let share = Double(dominant.flatMap { perDaypart[$0] } ?? 0) / Double(max(hours.count, 1))
        func percentile(_ fraction: Double) -> Int? {
            hours.isEmpty ? nil : hours[Int((fraction * Double(hours.count - 1)).rounded())]
        }
        let distinct = Set(moments.compactMap { places.index[$0.id] })
        return WhereFacts(daypart: dominant?.rawValue, daypartShare: share,
                          hourFrom: percentile(0.1), hourTo: percentile(0.9),
                          weekpart: weekpart(of: moments, calendar: calendar),
                          places: distinct.isEmpty ? nil : distinct.count)
    }

    /// Weekend is Saturday and Sunday.
    static func weekpart(of moments: [Moment], calendar: Calendar) -> String {
        let weekend = moments.filter {
            let weekday = calendar.component(.weekday, from: $0.start)
            return weekday == 1 || weekday == 7
        }.count
        let total = Double(max(moments.count, 1))
        if Double(weekend) / total >= weekpartShare { return "weekend" }
        if Double(moments.count - weekend) / total >= weekpartShare { return "weekday" }
        return "mixed"
    }

    private struct Ranked {
        let key: String
        let moments: [Moment]
        let days: Int
    }

    private struct Places {
        /// Moment id -> place number, for moments with a location.
        var index: [String: Int] = [:]
        var centers: [GeoPoint] = []
    }

    /// Time order; each located moment joins the nearest place whose center
    /// (mean of its members) is within 300 m, else starts one.
    private static func assignPlaces(_ members: [Moment]) -> Places {
        var places = Places()
        var points: [[GeoPoint]] = []
        for moment in members {
            guard let location = moment.location else { continue }
            var nearest: (slot: Int, km: Double)?
            for (slot, center) in places.centers.enumerated() {
                let distance = center.km(to: location)
                if distance <= placeKm, nearest == nil || distance < nearest!.km {
                    nearest = (slot, distance)
                }
            }
            if let slot = nearest?.slot {
                points[slot].append(location)
                places.centers[slot] = GeoPoint.center(of: points[slot]) ?? location
                places.index[moment.id] = slot
            } else {
                places.index[moment.id] = places.centers.count
                places.centers.append(location)
                points.append([location])
            }
        }
        return places
    }
}
