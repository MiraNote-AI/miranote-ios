import Foundation

/// One photo chosen for the judge, with the group it has in each split
/// (`A0` / `B0` when it is in none).
struct SampledPhoto: Equatable {
    let momentId: String
    /// The moment's representative photo.
    let photoId: String
    // swiftlint:disable identifier_name
    let a: String
    let b: String
    // swiftlint:enable identifier_name
}

/// Chooses the small set of photos a pile is judged on (spec S6). The same
/// photos carry an A label and a B label, so there are `max` photos, not two
/// sets. At most one per day.
enum ThemeSampler {
    /// Every group should have this many photos.
    static let floorPerGroup = 2
    /// About this share of the photos is added by group size (round 2).
    static let sizeShare = 0.3
    /// About this share is kept for "other" (round 3).
    static let otherShare = 0.2
    /// MMR weight of closeness to the pile's center (against sameness with the chosen).
    static let mmrRelevance: Float = 0.4

    // swiftlint:disable:next identifier_name
    static func pick(_ pile: Pile, moments: [String: Moment], a: [SplitGroup], b: [SplitGroup],
                     aesthetics: [String: Double], max limit: Int = 20) -> [SampledPhoto] {
        let members = pile.momentIds.compactMap { moments[$0] }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        guard limit > 0, !members.isEmpty else { return [] }
        var run = Run(pile: pile, members: members, groupsA: a, groupsB: b, aesthetics: aesthetics, limit: limit)

        if members.count <= limit { return run.bestOfEachDay() }

        // Round 1: the floor.
        run.fill(limit, targets: run.floorTargets)
        // Round 2: about 30% more, by days in proportion within each split.
        let other = Int((Double(limit) * otherShare).rounded())
        let wanted = Int((Double(limit) * sizeShare).rounded())
        let extra = Swift.max(0, Swift.min(wanted, limit - run.chosen.count - other))
        if extra > 0 {
            var targets = run.floorTargets
            for split in [a, b] {
                for (id, share) in apportion(extra, split) { targets[id, default: floorPerGroup] += share }
            }
            run.fill(extra, targets: targets)
        }
        // Round 3: the rest, the most different from what is chosen (MMR).
        run.fillByMMR()
        return run.result()
    }

    private struct Share {
        let id: String
        var whole: Int
        let rest: Double
    }

    /// Splits `total` over the groups in proportion to their days (largest remainder).
    private static func apportion(_ total: Int, _ groups: [SplitGroup]) -> [(String, Int)] {
        let days = groups.reduce(0) { $0 + $1.days }
        guard days > 0 else { return [] }
        var rows = groups.map { group -> Share in
            let exact = Double(total * group.days) / Double(days)
            return Share(id: group.id, whole: Int(exact), rest: exact - Double(Int(exact)))
        }
        var left = total - rows.reduce(0) { $0 + $1.whole }
        let order = rows.indices.sorted { rows[$0].rest != rows[$1].rest ? rows[$0].rest > rows[$1].rest : $0 < $1 }
        for index in order where left > 0 {
            rows[index].whole += 1
            left -= 1
        }
        return rows.map { ($0.id, $0.whole) }
    }

    /// The state of one sampling.
    private struct Run {
        let pile: Pile
        let members: [Moment]
        let aesthetics: [String: Double]
        let limit: Int
        var groupOfA: [String: String] = [:]
        var groupOfB: [String: String] = [:]
        var floorTargets: [String: Int] = [:]
        var chosen: [Moment] = []
        var usedDays = Set<String>()

        init(pile: Pile, members: [Moment], groupsA: [SplitGroup], groupsB: [SplitGroup],
             aesthetics: [String: Double], limit: Int) {
            self.pile = pile
            self.members = members
            self.aesthetics = aesthetics
            self.limit = limit
            for group in groupsA { for id in group.momentIds { groupOfA[id] = group.id } }
            for group in groupsB { for id in group.momentIds { groupOfB[id] = group.id } }
            for group in groupsA + groupsB { floorTargets[group.id] = floorPerGroup }
        }

        func score(_ moment: Moment) -> Double { aesthetics[moment.id] ?? 0 }

        /// Higher aesthetics first; the smaller id wins a tie.
        func better(_ first: Moment, _ second: Moment) -> Bool {
            score(first) != score(second) ? score(first) > score(second) : first.id < second.id
        }

        func groups(of moment: Moment) -> [String] {
            [groupOfA[moment.id], groupOfB[moment.id]].compactMap { $0 }
        }

        mutating func take(_ moment: Moment) {
            chosen.append(moment)
            usedDays.insert(moment.day)
        }

        func result() -> [SampledPhoto] {
            chosen.sorted { ($0.start, $0.id) < ($1.start, $1.id) }.map {
                SampledPhoto(momentId: $0.id, photoId: $0.id, a: groupOfA[$0.id] ?? "A0", b: groupOfB[$0.id] ?? "B0")
            }
        }

        /// Few moments: every day's best one.
        mutating func bestOfEachDay() -> [SampledPhoto] {
            var best: [String: Moment] = [:]
            for moment in members where best[moment.day].map({ better(moment, $0) }) ?? true {
                best[moment.day] = moment
            }
            chosen = Array(best.values)
            return result()
        }

        /// Repeatedly takes the unused-day moment that fills the most still
        /// missing group slots (A and B together), then the better one.
        mutating func fill(_ budget: Int, targets: [String: Int]) {
            var count: [String: Int] = [:]
            for moment in chosen { for id in groups(of: moment) { count[id, default: 0] += 1 } }
            var taken = 0
            while taken < budget, chosen.count < limit {
                var best: Moment?
                var bestGain = 0
                for moment in members where !usedDays.contains(moment.day) {
                    let gain = groups(of: moment).filter { (targets[$0] ?? 0) > (count[$0] ?? 0) }.count
                    if gain > bestGain || (gain > 0 && gain == bestGain && best.map { better(moment, $0) } == true) {
                        best = moment
                        bestGain = gain
                    }
                }
                guard let pick = best else { return }
                take(pick)
                taken += 1
                for id in groups(of: pick) { count[id, default: 0] += 1 }
            }
        }

        /// The unused-day moment close to the pile but unlike what is chosen.
        mutating func fillByMMR() {
            while chosen.count < limit {
                var best: Moment?
                var bestScore: Float = 0
                for moment in members where !usedDays.contains(moment.day) {
                    let value = mmr(moment)
                    let tied = value == bestScore && best.map { better(moment, $0) } == true
                    if best == nil || value > bestScore || tied {
                        best = moment
                        bestScore = value
                    }
                }
                guard let pick = best else { return }
                take(pick)
            }
        }

        private func mmr(_ moment: Moment) -> Float {
            let relevance = 1 - MomentBuilder.cosineDistance(moment.vector, pile.center)
            let redundancy = chosen.map { 1 - MomentBuilder.cosineDistance(moment.vector, $0.vector) }.max() ?? 0
            return ThemeSampler.mmrRelevance * relevance - (1 - ThemeSampler.mmrRelevance) * redundancy
        }
    }
}
