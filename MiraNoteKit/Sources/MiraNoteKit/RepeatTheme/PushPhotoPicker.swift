import Foundation

/// Which of a theme's photos a push checks and shows (S10 steps 3, 5, 6).
public enum PushPhotoPicker {
    /// Round 2 takes at most this many candidates (decision 12).
    public static let maxCandidates = 15
    /// A push shows this many photos when there are more (decision 13).
    public static let defaultCount = 7
    /// The repeat compose takes 5-9 photos.
    public static let minPhotos = 5
    public static let maxPhotos = 9
    /// MMR's weight on looking like the theme (against differing from the
    /// photos already picked).
    static let likeness: Float = 0.5

    // swiftlint:disable function_parameter_count
    /// Decision 12: one photo a day -- the strongest `evidence` (a content
    /// theme's label confidence, missing: 0), then the highest aesthetics
    /// (missing: 0.5, as iOS 17), a tie to the one nearest `center`, then the earlier.
    /// The days whose photo a life-fragment push used (`lifeFragmentPhotos`)
    /// go after the others: over 15 days, the others are spaced first and
    /// those days only fill what is left. Spaced = evenly over time, the
    /// first and last day kept. The others by date, then those by date.
    public static func candidates(_ ids: [String], takenAt: [String: Date], days: [String: String],
                                  aesthetics: [String: Double], vectors: [String: [Float]], center: [Float],
                                  lifeFragmentPhotos: Set<String>, evidence: [String: Float] = [:]) -> [String] {
        var best: [String: String] = [:]
        func better(_ first: String, _ second: String) -> Bool {
            let (firstEvidence, secondEvidence) = (evidence[first] ?? 0, evidence[second] ?? 0)
            if firstEvidence != secondEvidence { return firstEvidence > secondEvidence }
            let (firstScore, secondScore) = (aesthetics[first] ?? 0.5, aesthetics[second] ?? 0.5)
            if firstScore != secondScore { return firstScore > secondScore }
            let firstDistance = MomentBuilder.cosineDistance(vectors[first] ?? [], center)
            let secondDistance = MomentBuilder.cosineDistance(vectors[second] ?? [], center)
            if firstDistance != secondDistance { return firstDistance < secondDistance }
            return earlier(first, second, takenAt)
        }
        for id in ids {
            guard takenAt[id] != nil, let day = days[id] else { continue }
            if let held = best[day], !better(id, held) { continue }
            best[day] = id
        }
        let byDate = best.values.sorted { earlier($0, $1, takenAt) }
        let others = byDate.filter { !lifeFragmentPhotos.contains($0) }
        let used = byDate.filter(lifeFragmentPhotos.contains)
        let first = spaced(others, count: maxCandidates, takenAt: takenAt)
        return first + spaced(used, count: maxCandidates - first.count, takenAt: takenAt)
    }
    // swiftlint:enable function_parameter_count

    /// Decision 13, after round 2: the earliest and the latest, then by
    /// MMR on the prints (like `center`, unlike those picked) until 7 --
    /// or all of them when 5-6 are left -- in date order.
    public static func pick(_ ids: [String], vectors: [String: [Float]], takenAt: [String: Date],
                            center: [Float]) -> [String] {
        var left = Array(Set(ids)).filter { takenAt[$0] != nil }.sorted { earlier($0, $1, takenAt) }
        guard left.count > defaultCount - 1 else { return left }
        var picked = [left.removeFirst(), left.removeLast()]
        func similarity(_ first: [Float], _ second: [Float]) -> Float {
            1 - MomentBuilder.cosineDistance(first, second)
        }
        while picked.count < defaultCount, !left.isEmpty {
            var choice = 0
            var top = -Float.infinity
            for (index, id) in left.enumerated() {
                let vector = vectors[id] ?? []
                let like = center.isEmpty ? 0 : similarity(vector, center)
                let nearest = picked.map { similarity(vector, vectors[$0] ?? []) }.max() ?? 0
                let score = likeness * like - (1 - likeness) * nearest
                if score > top {
                    top = score
                    choice = index
                }
            }
            picked.append(left.remove(at: choice))
        }
        return picked.sorted { earlier($0, $1, takenAt) }
    }

    /// The local `yyyy-MM-dd` of `date`.
    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// At most `count` of `sorted` (by date), evenly over time: the first
    /// and the last, then for each even step the nearest not yet taken.
    private static func spaced(_ sorted: [String], count: Int, takenAt: [String: Date]) -> [String] {
        guard sorted.count > count else { return sorted }
        guard count > 1 else { return Array(sorted.prefix(max(0, count))) }
        let times = sorted.map { takenAt[$0]?.timeIntervalSince1970 ?? 0 }
        var taken: Set<Int> = [0, sorted.count - 1]
        let step = ((times.last ?? 0) - (times.first ?? 0)) / Double(count - 1)
        for target in 1..<(count - 1) {
            let time = (times.first ?? 0) + Double(target) * step
            let nearest = (1..<(sorted.count - 1)).filter { !taken.contains($0) }
                .min { abs(times[$0] - time) < abs(times[$1] - time) }
            if let nearest { taken.insert(nearest) }
        }
        return taken.sorted().map { sorted[$0] }
    }

    private static func earlier(_ first: String, _ second: String, _ takenAt: [String: Date]) -> Bool {
        let (firstTime, secondTime) = (takenAt[first] ?? .distantPast, takenAt[second] ?? .distantPast)
        return firstTime != secondTime ? firstTime < secondTime : first < second
    }
}
