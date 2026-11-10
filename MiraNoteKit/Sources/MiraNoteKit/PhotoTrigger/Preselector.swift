import Foundation

/// One photo picked to go to the AI, and the rule that picked it.
public struct Preselected: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        /// Ten or fewer unique photos: every one goes.
        case all
        /// Step 1: favourited or edited.
        case marked
        /// Step 2: the best photo of a moment.
        case moment
        /// Step 3: a category not yet covered.
        case newCategory
        /// Step 4: the person floor.
        case person
        /// Step 5: MMR fill.
        case fill
    }

    public let id: String
    public let reason: Reason
    /// `0.6 quality + 0.2 has people + 0.2 marked`.
    public let score: Double
    /// Photos it stands for: itself plus its near-duplicates.
    public let represents: Int
}

/// Picks at most ten photos of a fragment to send to the AI
/// (the v1 preselection rule): all of them when ten or fewer are unique, else
/// steps 1-5 in order -- marked, one per moment, new categories, the
/// person floor, then an MMR fill. Only unique photos are picked; the
/// result is in time order.
public enum Preselector {
    public static let slots = 10
    static let maxMarked = 3
    static let maxNewCategories = 4
    /// The dedupe threshold doubles as "alike": a person photo further than
    /// this from the chosen ones counts as "not like them" (step 4).
    static let alikeDistance: Float = FragmentGrouper.duplicateDistance

    struct Candidate {
        let photo: GroupablePhoto
        let score: Double
        let marked: Bool
        let hasPeople: Bool
        let broad: Set<BroadCategory>
    }

    public static func select(
        _ fragment: Fragment, analyses: [String: PhotoAnalysis], library: [String: LibraryAsset],
        distance: (String, String) -> Float?
    ) -> [Preselected] {
        let candidates = fragment.uniquePhotos.map { photo -> Candidate in
            let analysis = analyses[photo.id]
            let asset = library[photo.id]
            let marked = (asset?.isFavorite ?? false) || (asset?.isEdited ?? false)
            let hasPeople = (analysis?.faces ?? 0) > 0 || (analysis?.broad.contains(.people) ?? false)
            let quality = analysis?.quality ?? 0.5
            return Candidate(photo: photo, score: 0.6 * quality + 0.2 * (hasPeople ? 1 : 0) + 0.2 * (marked ? 1 : 0),
                             marked: marked, hasPeople: hasPeople, broad: analysis?.broad ?? [])
        }
        let picks: [(Candidate, Preselected.Reason)] = withoutActuallyEscaping(distance) { distance in
            var picker = Picker(candidates: candidates, distance: distance)
            guard candidates.count > slots else { return candidates.map { ($0, .all) } }
            picker.marked()
            picker.moments()
            picker.categories()
            picker.people()
            picker.fill()
            return picker.picks
        }
        let represents = fragment.represents
        return picks.sorted { $0.0.photo.takenAt < $1.0.photo.takenAt }.map {
            Preselected(id: $0.0.photo.id, reason: $0.1, score: $0.0.score, represents: represents[$0.0.photo.id] ?? 1)
        }
    }

    /// Fills the ten slots step by step.
    struct Picker {
        let candidates: [Candidate]
        let distance: (String, String) -> Float?
        private(set) var picks: [(Candidate, Preselected.Reason)] = []

        init(candidates: [Candidate], distance: @escaping (String, String) -> Float?) {
            self.candidates = candidates
            self.distance = distance
        }

        private var room: Bool { picks.count < slots }

        private func isPicked(_ candidate: Candidate) -> Bool {
            picks.contains { $0.0.photo.id == candidate.photo.id }
        }

        private mutating func pick(_ candidate: Candidate, _ reason: Preselected.Reason) {
            guard room, !isPicked(candidate) else { return }
            picks.append((candidate, reason))
        }

        /// Higher score first; the earlier photo on a tie.
        private static func byScore(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.photo.takenAt < rhs.photo.takenAt
        }

        /// FeaturePrint distance to the nearest of `chosen`, capped at 1;
        /// a missing print counts as entirely unlike.
        private func dissimilarity(_ candidate: Candidate, to chosen: [Candidate]) -> Double {
            chosen.map { Double(min(1, distance($0.photo.id, candidate.photo.id) ?? 1)) }.min() ?? 1
        }

        /// Step 1: favourited or edited, at most three.
        mutating func marked() {
            for candidate in candidates.filter(\.marked).sorted(by: Self.byScore).prefix(maxMarked) {
                pick(candidate, .marked)
            }
        }

        /// Step 2: every moment its best photo, unless a pick covers it.
        mutating func moments() {
            let covered = Set(picks.map(\.0.photo.id))
            for moment in Preselector.momentOrder(Preselector.moments(candidates), covered: covered) where room {
                if let best = moment.sorted(by: Self.byScore).first { pick(best, .moment) }
            }
        }

        /// Step 3: categories present but not covered, by priority, at most four.
        mutating func categories() {
            var added = 0
            let rank = { (category: BroadCategory) in
                (category.priority, BroadCategory.allCases.firstIndex(of: category) ?? 0)
            }
            let present = Set(candidates.flatMap(\.broad)).sorted { rank($0) < rank($1) }
            for category in present where added < maxNewCategories && room {
                guard !picks.contains(where: { $0.0.broad.contains(category) }),
                      let best = candidates.filter({ $0.broad.contains(category) && !isPicked($0) })
                          .sorted(by: Self.byScore).first
                else { continue }
                pick(best, .newCategory)
                added += 1
            }
        }

        /// Step 4: a person photo at least -- in place of another pick when
        /// the steps before filled every slot; one more if one is unlike it.
        mutating func people() {
            let people = candidates.filter(\.hasPeople)
            if !picks.contains(where: { $0.0.hasPeople }), let best = people.sorted(by: Self.byScore).first {
                if !room { makeRoom(for: best) }
                pick(best, .person)
            }
            let pickedPeople = picks.map(\.0).filter(\.hasPeople)
            guard pickedPeople.count == 1 else { return }
            let unlike = people
                .filter { !isPicked($0) && dissimilarity($0, to: pickedPeople) > Double(alikeDistance) }
                .max { dissimilarity($0, to: pickedPeople) < dissimilarity($1, to: pickedPeople) }
            if let unlike { pick(unlike, .person) }
        }

        /// Frees one slot for `person`: the pick from its own moment when
        /// there is one (the moment stays covered), else the last pick made
        /// -- the least deserving moment or category. Marked photos stay.
        private mutating func makeRoom(for person: Candidate) {
            let own = Preselector.moments(candidates).first { $0.contains { $0.photo.id == person.photo.id } }
            let ownIds = Set((own ?? []).map(\.photo.id))
            let removable = picks.indices.filter { picks[$0].1 != .marked }
            guard let index = removable.first(where: { ownIds.contains(picks[$0].0.photo.id) }) ?? removable.last
            else { return }
            picks.remove(at: index)
        }

        /// Step 5: MMR, half score and half unlikeness to what is picked.
        mutating func fill() {
            while room {
                let chosen = picks.map(\.0)
                let snapshot = self
                let value = { (candidate: Candidate) in
                    0.5 * candidate.score + 0.5 * snapshot.dissimilarity(candidate, to: chosen)
                }
                let next = candidates.filter { !isPicked($0) }.max { lhs, rhs in
                    value(lhs) != value(rhs) ? value(lhs) < value(rhs) : lhs.photo.takenAt > rhs.photo.takenAt
                }
                guard let next else { return }
                pick(next, .fill)
            }
        }
    }

    /// Unique photos split at pauses of 20 minutes or more.
    static func moments(_ candidates: [Candidate]) -> [[Candidate]] {
        var moments: [[Candidate]] = []
        for candidate in candidates {
            if let last = moments.last?.last,
               candidate.photo.takenAt.timeIntervalSince(last.photo.takenAt) < FragmentScorer.momentGap {
                moments[moments.count - 1].append(candidate)
            } else {
                moments.append([candidate])
            }
        }
        return moments
    }

    /// The moments still to cover, most deserving first: the first and the
    /// last, then those with more photos, a tie going to the one further in
    /// time from the moments already chosen.
    static func momentOrder(_ moments: [[Candidate]], covered: Set<String>) -> [[Candidate]] {
        let center = { (moment: [Candidate]) -> TimeInterval in
            let times = moment.map { $0.photo.takenAt.timeIntervalSinceReferenceDate }
            return times.reduce(0, +) / Double(max(1, times.count))
        }
        var chosen = moments.filter { $0.contains { covered.contains($0.photo.id) } }
        var open = moments.filter { !$0.contains { covered.contains($0.photo.id) } }
        var ordered: [[Candidate]] = []
        for end in [moments.first, moments.last].compactMap({ $0 }) {
            if let index = open.firstIndex(where: { $0.first?.photo.id == end.first?.photo.id }) {
                ordered.append(open.remove(at: index))
                chosen.append(end)
            }
        }
        while !open.isEmpty {
            let spread = { (moment: [Candidate]) -> TimeInterval in
                chosen.map { abs(center($0) - center(moment)) }.min() ?? .infinity
            }
            let index = open.indices.max { lhs, rhs in
                open[lhs].count != open[rhs].count ? open[lhs].count < open[rhs].count
                    : spread(open[lhs]) < spread(open[rhs])
            }!
            chosen.append(open[index])
            ordered.append(open.remove(at: index))
        }
        return ordered
    }
}
