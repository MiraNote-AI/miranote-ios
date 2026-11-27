import Foundation

/// Where a theme stands in the library.
public enum ThemeStatus: String, Codable, Sendable {
    case active, frozen, retired, blocked, sensitive
}

/// One big or small repeat theme in the library, known by its id; the name
/// is just a column. Stays on the phone: the row is stored, never sent.
public struct ThemeRow: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case big, small
    }

    /// A UUID string.
    public var id: String
    public var kind: Kind
    /// The big theme's id (small themes only).
    public var parentId: String?
    public var name: String
    public var noun: String
    /// What is the same every time.
    public var samePart: String
    /// `A`, `B` or `none` (big themes only).
    public var split: String?
    public var status: ThemeStatus
    /// The mean look, unit length: of a big theme's members, or of the
    /// moments a content small theme was made from.
    /// Nil for occasion small themes and for small rows stored before
    /// small themes had one.
    public var center: [Float]?
    /// How tonight's members are picked from the big theme's (small themes only).
    /// An occasion rule holds place centers: on disk only, never sent anywhere.
    public var rule: SubRule?
    /// Photo ids.
    public var members: [String]
    /// The member count when Qwen last looked at the theme.
    public var lastAskedCount: Int
    /// Followed tonight at 20-50%: shown yellow on the debug page.
    public var flagged: Bool
    /// Tonight's claim ratio (big themes only).
    public var followRatio: Double?
    public var `where`: WhereFacts?

    public init(id: String, kind: Kind, parentId: String?, name: String, noun: String, samePart: String,
                split: String?, status: ThemeStatus, center: [Float]?, rule: SubRule?, members: [String],
                lastAskedCount: Int, flagged: Bool, followRatio: Double?, where: WhereFacts?) {
        self.id = id
        self.kind = kind
        self.parentId = parentId
        self.name = name
        self.noun = noun
        self.samePart = samePart
        self.split = split
        self.status = status
        self.center = center
        self.rule = rule
        self.members = members
        self.lastAskedCount = lastAskedCount
        self.flagged = flagged
        self.followRatio = followRatio
        self.where = `where`
    }
}

/// What the old big themes did with tonight's piles.
struct ClaimResult: Equatable {
    /// Theme id -> the index of the pile it follows.
    var follows: [String: Int]
    /// Theme id -> its best ratio (0 when none of its old photos is in the window).
    var ratios: [String: Double]
    /// Followed at 20-50%.
    var flagged: Set<String>
    /// Below 20%: follows nothing, keeps its old list.
    var frozen: Set<String>
    /// Theme id -> tonight's photo ids (the old list for a frozen theme).
    var members: [String: [String]]
    /// Indices of the piles no theme follows, ascending.
    var newPiles: [Int]
}

/// Old big themes claim tonight's piles without asking Qwen (spec 6.6, S11
/// item 3: grow, slight change, split, merge, mismatch).
///
/// Every big row claims whatever its status: a sensitive or blocked theme
/// still follows its pile, so that pile is not offered as a new one and sent
/// to Qwen again. Small rows are ignored here (`SubThemeRule` does them).
enum ThemeClaim {
    /// At or above this ratio a theme follows its pile.
    static let followRatio = 0.5
    /// At or above this (and below `followRatio`) it follows and is flagged;
    /// below it the theme freezes.
    static let flagRatio = 0.2

    /// `moments` by id; `window` is the photo ids still in the time window.
    /// A theme's ratio for a pile = its old photos in the window that are in
    /// the pile tonight / its old photos in the window. It follows its best
    /// pile (tie: more distinct days of its old photos there, then the lower
    /// index). One theme per pile gets the whole pile; several share it: each
    /// keeps its own old photos, the rest go to the nearest theme center.
    static func claim(_ bigThemes: [ThemeRow], piles: [Pile], moments: [String: Moment],
                      window: Set<String>) -> ClaimResult {
        var momentOf: [String: (pile: Int, moment: Moment)] = [:]
        for (index, pile) in piles.enumerated() {
            for moment in pile.momentIds.compactMap({ moments[$0] }) {
                for photoId in moment.photoIds { momentOf[photoId] = (index, moment) }
            }
        }

        var result = ClaimResult(follows: [:], ratios: [:], flagged: [], frozen: [], members: [:], newPiles: [])
        let themes = bigThemes.filter { $0.kind == .big }
        for theme in themes {
            let (best, ratio) = bestPile(theme, window: window, momentOf: momentOf)
            result.ratios[theme.id] = ratio
            if let best, ratio >= flagRatio {
                result.follows[theme.id] = best
                if ThemeRow.flags(ratio: ratio) { result.flagged.insert(theme.id) }
            } else {
                result.frozen.insert(theme.id)
                result.members[theme.id] = theme.members
            }
        }

        for (index, pile) in piles.enumerated() {
            let followers = themes.filter { result.follows[$0.id] == index }
            let photos = pile.momentIds.compactMap { moments[$0] }.flatMap(\.photoIds)
            switch followers.count {
            case 0: result.newPiles.append(index)
            case 1: result.members[followers[0].id] = photos
            default:
                result.members.merge(share(photos, among: followers, momentOf: momentOf)) { _, new in new }
            }
        }
        return result
    }

    /// The pile holding the largest share of the theme's old photos that are
    /// still in the window, and that share; nil and 0 when no pile holds any
    /// (or none is in the window).
    private static func bestPile(_ theme: ThemeRow, window: Set<String>,
                                 momentOf: [String: (pile: Int, moment: Moment)]) -> (Int?, Double) {
        let old = Set(theme.members).filter(window.contains)
        var counts: [Int: Int] = [:]
        var days: [Int: Set<String>] = [:]
        for photoId in old {
            guard let (index, moment) = momentOf[photoId] else { continue }
            counts[index, default: 0] += 1
            days[index, default: []].insert(moment.day)
        }
        let best = counts.keys.max { first, second in
            if counts[first] != counts[second] { return counts[first]! < counts[second]! }
            let firstDays = days[first]?.count ?? 0
            let secondDays = days[second]?.count ?? 0
            if firstDays != secondDays { return firstDays < secondDays }
            return first > second
        }
        return (best, best.map { Double(counts[$0]!) / Double(old.count) } ?? 0)
    }

    /// One pile followed by several themes: a photo on a theme's old list
    /// stays with it; any other goes to the theme whose center is nearest
    /// its moment's look (tie: the lower id). Lists keep the pile's order.
    private static func share(_ photos: [String], among followers: [ThemeRow],
                              momentOf: [String: (pile: Int, moment: Moment)]) -> [String: [String]] {
        let owners = followers.map { (id: $0.id, old: Set($0.members), center: $0.center ?? []) }
        var shares = Dictionary(uniqueKeysWithValues: owners.map { ($0.id, [String]()) })
        for photoId in photos {
            let own = owners.filter { $0.old.contains(photoId) }
            if !own.isEmpty {
                for owner in own { shares[owner.id, default: []].append(photoId) }
                continue
            }
            let vector = momentOf[photoId]?.moment.vector ?? []
            let nearest = owners.min { first, second in
                let firstDistance = MomentBuilder.cosineDistance(vector, first.center)
                let secondDistance = MomentBuilder.cosineDistance(vector, second.center)
                return firstDistance != secondDistance ? firstDistance < secondDistance : first.id < second.id
            }
            if let nearest { shares[nearest.id, default: []].append(photoId) }
        }
        return shares
    }
}

extension ThemeRow {
    /// A followed theme whose share of old photos in its pile is 20% up to,
    /// not including, 50% is flagged (spec C2: 50% and up follows, under 20%
    /// freezes). The debug page reads `flagged`, set by this rule.
    public static func flags(ratio: Double) -> Bool {
        ratio >= ThemeClaim.flagRatio && ratio < ThemeClaim.followRatio
    }
}
