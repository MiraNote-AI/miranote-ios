import Foundation

/// A press's grouping as JSON, for the debug view phase 2 will add and for
/// checking the grouping against the prototype (acceptance H4): T and its
/// fallback, every cut and why, each fragment with its score, and the
/// dropped segments. Written locally only; it names photos by their
/// original file names and localIdentifiers, never their coordinates.
public enum GroupingReport {
    public static var defaultFile: URL {
        PhotoTriggerPaths.root.appendingPathComponent("last-grouping.json")
    }

    static func make(_ grouping: GroupingResult, scores: [String: FragmentScore],
                     library: [String: LibraryAsset], utility: [String], calendar: Calendar) -> Data? {
        let iso = ISO8601DateFormatter()
        iso.timeZone = calendar.timeZone
        let name = { (id: String) in library[id]?.originalFilename ?? id }
        let photo = { (item: GroupablePhoto) -> [String: Any] in
            ["file": name(item.id), "id": item.id, "taken": iso.string(from: item.takenAt),
             "gps": item.location != nil]
        }
        let fragments = grouping.fragments.map { fragment -> [String: Any] in
            var entry: [String: Any] = [
                "day": fragment.belongsTo, "start": iso.string(from: fragment.start),
                "end": iso.string(from: fragment.end), "unique": fragment.uniqueCount,
                "photos": fragment.photos.map(photo),
                "duplicates": fragment.representative.map { [name($0.key), name($0.value)] }
            ]
            if let score = scores[ComposeMeta.groupKey(fragment)] {
                entry["score"] = ["total": score.total, "r": score.r, "s": score.s, "p": score.p, "n": score.n,
                                  "u": score.u, "a": score.a, "pushable": score.pushable]
            }
            return entry
        }
        let report: [String: Any] = [
            "threshold_seconds": grouping.threshold.value,
            "threshold_fallback": grouping.threshold.fallback?.rawValue ?? NSNull(),
            "cuts": grouping.cuts.map { ["after": name($0.after), "before": name($0.before), "rule": $0.rule.rawValue,
                                         "gap_min": Int($0.gap / 60), "km": $0.km ?? NSNull()] as [String: Any] },
            "fragments": fragments,
            "dropped": grouping.dropped.map { $0.map(photo) },
            "utility": utility.map(name)
        ]
        return try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    }
}
