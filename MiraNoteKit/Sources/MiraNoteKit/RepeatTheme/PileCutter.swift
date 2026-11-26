import Foundation

/// A candidate repeat theme: a subtree of moments that look alike and were
/// taken on enough different days, none of which dominates.
public struct Pile: Equatable, Sendable {
    /// The member moments' ids, by moment start.
    public let momentIds: [String]
    /// How many different days the moments fall on.
    public let days: Int
    /// The busiest day's moments over all moments.
    public let maxDayShare: Double
    /// The tree height (cosine distance) where the pile was cut.
    public let height: Float
    /// The mean of the moment vectors, scaled to unit length.
    public let center: [Float]

    public init(momentIds: [String], days: Int, maxDayShare: Double, height: Float, center: [Float]) {
        self.momentIds = momentIds
        self.days = days
        self.maxDayShare = maxDayShare
        self.height = height
        self.center = center
    }
}

/// Cuts the moment tree into piles, event-aware: a node that is one busy day
/// (an outing, a party) does not count as a theme, however many photos it has.
///
/// The rules, the same as the desktop reference script's `cut`:
/// - a node qualifies with at least `minDays` days and no day above `maxShare`;
/// - a leaf is never a pile;
/// - a node above `top` is always split;
/// - a qualifying node is a pile, unless both children are non-leaves that
///   qualify too, then they are tried instead;
/// - a node that does not qualify is split while its height is above `floor`,
///   and dropped once it is not.
enum PileCutter {
    static let top: Float = 0.5
    static let floor: Float = 0.2
    static let minDays = 5
    static let maxShare = 0.30

    /// `tree` must be `ThemeTree.build(moments.map(\.vector))`. Piles come
    /// most days first, then most moments, then by first moment id.
    static func cut(_ moments: [Moment], tree: ThemeTree) -> [Pile] {
        guard tree.leafCount == moments.count else {
            assertionFailure("the tree was built from other moments")
            return []
        }
        guard moments.count > 1 else { return [] }

        func qualifies(_ index: Int) -> Bool {
            let (days, share) = dayStats(tree.leaves(index), moments)
            return days >= minDays && share <= maxShare
        }

        var piles: [Int] = []
        var stack = [tree.root]
        while let index = stack.popLast() {
            guard let (left, right) = tree.children(index) else { continue }
            let height = tree.height(index)
            if height > top {
                stack.append(contentsOf: [right, left])
            } else if qualifies(index) {
                if tree.children(left) != nil, tree.children(right) != nil, qualifies(left), qualifies(right) {
                    stack.append(contentsOf: [right, left])
                } else {
                    piles.append(index)
                }
            } else if height > floor {
                stack.append(contentsOf: [right, left])
            }
        }

        return piles.map { pile($0, tree: tree, moments: moments) }
            .sorted { first, second in
                if first.days != second.days { return first.days > second.days }
                if first.momentIds.count != second.momentIds.count {
                    return first.momentIds.count > second.momentIds.count
                }
                return (first.momentIds.first ?? "") < (second.momentIds.first ?? "")
            }
    }

    /// Distinct days, and the busiest day's share of the moments.
    private static func dayStats(_ leaves: [Int], _ moments: [Moment]) -> (days: Int, share: Double) {
        var perDay: [String: Int] = [:]
        for leaf in leaves { perDay[moments[leaf].day, default: 0] += 1 }
        return (perDay.count, Double(perDay.values.max() ?? 0) / Double(max(leaves.count, 1)))
    }

    private static func pile(_ index: Int, tree: ThemeTree, moments: [Moment]) -> Pile {
        let leaves = tree.leaves(index)
        let members = leaves.map { moments[$0] }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        let (days, share) = dayStats(leaves, moments)

        // Summed in member order so the same moments give the same center.
        let center = MomentBuilder.meanCenter(members.map(\.vector))

        return Pile(momentIds: members.map(\.id), days: days, maxDayShare: share,
                    height: tree.height(index), center: center)
    }
}
