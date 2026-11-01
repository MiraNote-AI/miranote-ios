import Foundation

/// One press of the debug entry, from the library to a scheduled push
/// (handoff 4 and 7.5): read and analyse the photos, group, score, then
/// try the ranked groups -- at most three per press -- until one comes
/// back from the AI; save it, schedule its push.
///
/// "Push in 10 s" always starts at rank 1; "push next" one after the last
/// rank pushed (or, after three failures, after the last rank tried),
/// back to 1 past the end. The cursor lives as long as this object: a
/// relaunch starts again at 1.
public actor TriggerRun {
    public static let maxTries = 3

    private let deps: TriggerDependencies
    private var cursor: Int?
    public private(set) var isRunning = false
    /// Every progress step so far (tests, debug).
    public private(set) var history: [TriggerProgress] = []
    private var listeners: [AsyncStream<TriggerProgress>.Continuation] = []

    public init(_ dependencies: TriggerDependencies) {
        deps = dependencies
    }

    /// Progress from now on.
    public func progress() -> AsyncStream<TriggerProgress> {
        let (stream, continuation) = AsyncStream<TriggerProgress>.makeStream()
        listeners.append(continuation)
        return stream
    }

    /// "Push in 10 s": from rank 1.
    public func pushTop() async {
        await press(next: false)
    }

    /// "Push the next group".
    public func pushNext() async {
        await press(next: true)
    }

    private func report(_ step: TriggerProgress) {
        history.append(step)
        for listener in listeners { listener.yield(step) }
    }

    private func press(next: Bool) async {
        // A second press while one runs is ignored: no second job.
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        report(.preparing)
        guard await deps.notifier.requestPermission() else { return report(.failed(.notificationsOff)) }
        let access = await deps.library.requestAccess()
        guard access != .denied else { return report(.failed(.photosDenied)) }
        if access == .limited { report(.partialLibrary) }

        let ranking = await TriggerRanking.make(deps) { step in self.report(step) }
        guard !ranking.groups.isEmpty else { return report(.failed(.noFragment)) }
        await tryGroups(ranking, from: next ? (cursor ?? 1) : 1)
    }

    /// Up to three groups from `start`, wrapping past the last.
    private func tryGroups(_ ranking: TriggerRanking, from start: Int) async {
        let count = ranking.groups.count
        var rank = start
        if rank > count {
            rank = 1
            report(.wrapped)
        }
        let tries = min(Self.maxTries, count)
        for attempt in 0..<tries {
            switch await attemptGroup(ranking.groups[rank - 1], ranking: ranking) {
            case .pushed:
                cursor = rank + 1
                return
            case .stop(let failure):
                return report(.failed(failure))
            case .rejected(let message):
                let following = rank < count ? rank + 1 : 1
                guard attempt < tries - 1 else {
                    cursor = following
                    return report(.allThreeFailed)
                }
                report(.rejected(rank: rank, message: message, next: following))
                if following == 1 { report(.wrapped) }
                rank = following
            }
        }
    }

    private func attemptGroup(_ group: RankedGroup, ranking: TriggerRanking) async -> TriggerAttempt {
        let calendar = deps.calendar
        var place: String?
        if let center = group.fragment.center { place = await deps.places.name(for: center) }
        report(.askingAI(rank: group.rank, date: TriggerWords.shortDate(group.fragment.belongsTo), place: place,
                         count: group.fragment.uniqueCount))
        let picks = Preselector.select(group.fragment, analyses: ranking.analyses, library: ranking.library,
                                       distance: ranking.distance)
        let built = ComposeMeta.build(fragment: group.fragment, picks: picks, analyses: ranking.analyses,
                                      library: ranking.library, place: place,
                                      recentQuestionIds: deps.records.recentQuestionIds(), calendar: calendar)
        let memory: TriggerMemory
        var photoIds = built.photoIds
        if deps.fakeAI() {
            memory = FakeAIMemory.build(meta: built.meta, photoIds: built.photoIds, picks: picks, calendar: calendar,
                                        zh: deps.zh)
        } else {
            switch await ComposeSession(deps: deps).run(built.meta, photoIds: built.photoIds) {
            case .success(let composed):
                memory = composed.memory
                photoIds = composed.photoIds
            case .failure(let box): return box.attempt
            }
        }
        let record = PushRecord(pushId: UUID().uuidString, memory: memory, photoIds: photoIds,
                                createdAt: deps.now(), rank: group.rank, score: group.score.total,
                                bucket: memory.bucket)
        do {
            try deps.records.save(record)
        } catch {
            return .stop(.backend(error.localizedDescription))
        }
        guard await deps.notifier.schedule(record) else { return .stop(.notificationsOff) }
        report(.scheduled(rank: group.rank, score: group.score.total))
        return .pushed
    }
}

/// How one group's try ended.
enum TriggerAttempt: Sendable {
    case pushed
    case rejected(String)
    case stop(TriggerFailure)
}

/// `TriggerAttempt` carried through `Result`'s failure.
struct TriggerAttemptBox: Error {
    let attempt: TriggerAttempt
    init(_ attempt: TriggerAttempt) { self.attempt = attempt }
}

/// The library read, analysed, grouped and ranked for one press.
struct TriggerRanking: Sendable {
    static let groupingDays: Double = 61
    static let thresholdDays: Double = 90
    static let placeDays: Double = 365

    let groups: [RankedGroup]
    let analyses: [String: PhotoAnalysis]
    let library: [String: LibraryAsset]
    let prints: [String: Data]
    let analyzer: PhotoAnalyzing

    /// FeaturePrint distance between two photo ids.
    func distance(_ first: String, _ second: String) -> Float? {
        guard let one = prints[first], let two = prints[second] else { return nil }
        return analyzer.distance((first, one), (second, two))
    }

    static func make(_ deps: TriggerDependencies, report: (TriggerProgress) async -> Void) async -> TriggerRanking {
        let now = deps.now()
        let calendar = deps.calendar
        let since = { (days: Double) in now.addingTimeInterval(-days * 86_400) }
        let eligible = await deps.library.assets(since: since(placeDays), knownFilenames: deps.analyses.filenames())
            .filter { LibraryFilter.eligible($0, now: now) }
        let recent = eligible.filter { ($0.takenAt ?? .distantPast) >= since(groupingDays) }
        let all = await analyze(recent, deps: deps, report: report)
        let analyses = all.filter { !$0.value.isUtility }
        let utility = Set(all.filter(\.value.isUtility).keys)

        let gapDates = eligible.filter { !utility.contains($0.id) }.compactMap(\.takenAt)
            .filter { $0 >= since(thresholdDays) }
        let threshold = PersonalThreshold.compute(gaps: PersonalThreshold.gaps(between: gapDates))
        let groupable = recent.filter { !utility.contains($0.id) }.compactMap { asset in
            asset.takenAt.map {
                GroupablePhoto(id: asset.id, takenAt: $0, location: asset.location, burstId: asset.burstId)
            }
        }
        let library = Dictionary(eligible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let unranked = TriggerRanking(groups: [], analyses: analyses, library: library,
                                      prints: analyses.compactMapValues(\.featurePrint), analyzer: deps.analyzer)
        let grouping = FragmentGrouper.group(groupable, threshold: threshold, calendar: calendar,
                                             distance: unranked.distance)
        let past = eligible.compactMap { asset -> (day: String, point: GeoPoint)? in
            guard let point = asset.location, let date = asset.takenAt else { return nil }
            return (FragmentGrouper.belongsTo(date, calendar: calendar), point)
        }
        let scored = grouping.fragments.compactMap { fragment -> (Fragment, FragmentScore)? in
            guard let score = FragmentScorer.score(fragment, analyses: analyses, library: library, now: now,
                                                   calendar: calendar, pastLocations: past),
                  score.pushable else { return nil }
            return (fragment, score)
        }
        if let sink = deps.groupingReport {
            // Every scored fragment, pushable or not.
            var scores: [String: FragmentScore] = [:]
            for fragment in grouping.fragments {
                scores[ComposeMeta.groupKey(fragment)] = FragmentScorer.score(
                    fragment, analyses: analyses, library: library, now: now, calendar: calendar, pastLocations: past)
            }
            if let data = GroupingReport.make(grouping, scores: scores, library: library, utility: Array(utility),
                                              calendar: calendar) { sink(data) }
        }
        let groups = scored.sorted { $0.1.total > $1.1.total }.enumerated().map {
            RankedGroup(rank: $0.offset + 1, fragment: $0.element.0, score: $0.element.1)
        }
        return TriggerRanking(groups: groups, analyses: analyses, library: library, prints: unranked.prints,
                              analyzer: deps.analyzer)
    }

    /// Every recent photo's analysis: saved ones from disk, the rest
    /// analysed now and saved one by one, so an interrupted run resumes.
    private static func analyze(_ assets: [LibraryAsset], deps: TriggerDependencies,
                                report: (TriggerProgress) async -> Void) async -> [String: PhotoAnalysis] {
        let store = deps.analyses
        let saved = store.analyzedIds()
        var results: [String: PhotoAnalysis] = [:]
        var todo: [String] = []
        for asset in assets {
            if saved.contains(asset.id), let analysis = store.load(asset.id) {
                results[asset.id] = analysis
            } else {
                todo.append(asset.id)
            }
        }
        var done = results.count
        await report(.analyzing(done: done, total: assets.count))
        let names = Dictionary(assets.map { ($0.id, $0.originalFilename) }, uniquingKeysWith: { first, _ in first })
        for id in todo {
            if let analysis = await deps.analyzer.analyze(id) {
                // The file name goes with it: later presses need not ask PhotoKit.
                let named = analysis.with(originalFilename: names[id] ?? nil)
                try? store.save(named)
                results[id] = named
            }
            done += 1
            await report(.analyzing(done: done, total: assets.count))
        }
        return results
    }
}
