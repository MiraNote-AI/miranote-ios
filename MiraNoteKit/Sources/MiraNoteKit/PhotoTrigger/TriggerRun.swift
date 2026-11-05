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
                    return report(.allFailed(tried: tries))
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
        let picks = ranking.preselect(group.fragment)
        let built = ComposeMeta.build(fragment: group.fragment, picks: picks, analyses: ranking.analyses,
                                      library: ranking.library, place: place,
                                      bucket: group.score.bucket,
                                      // A press outside the nights: none around it.
                                      recentQuestionTypes: [], calendar: calendar)
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
                                bucket: memory.bucket, bucketId: group.score.bucket,
                                belongsTo: group.fragment.belongsTo, isDebug: true)
        do {
            try deps.records.save(record)
        } catch {
            return .stop(.backend(error.localizedDescription))
        }
        let identifier = PushIdentifier.make(record.pushId)
        guard await deps.notifier.schedule(record, identifier: identifier, at: nil, relevance: group.score.total)
        else { return .stop(.notificationsOff) }
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

/// The library read, analysed, grouped and ranked for one press or one
/// scheduling run.
struct TriggerRanking: Sendable {
    static let groupingDays: Double = 61
    static let thresholdDays: Double = 90
    /// Place novelty looks back three months (decision 11-04).
    static let placeDays: Double = 90
    /// A photo whose analysis failed is tried again this long after.
    static let retryAfter: TimeInterval = 86_400
    /// Failures are written down every this many, so a run killed midway
    /// still remembers most of them.
    static let failuresBatch = 20

    /// Pushable fragments ranked at `now` (the phase-1 press order).
    let groups: [RankedGroup]
    /// Every fragment of the grouping, pushable or not.
    let fragments: [Fragment]
    /// Non-utility analyses of the recent photos.
    let analyses: [String: PhotoAnalysis]
    let library: [String: LibraryAsset]
    let prints: [String: Data]
    let analyzer: PhotoAnalyzing
    /// Recent photos left out as documents, receipts and the like.
    let utility: [String]
    /// Recent analysed non-utility photos, newest first.
    let recentIds: [String]
    /// The last 90 days' photo positions by belongs-to day (N).
    let pastLocations: [(day: String, point: GeoPoint)]
    /// The T the grouping used.
    let threshold: ThresholdResult

    /// FeaturePrint distance between two photo ids.
    func distance(_ first: String, _ second: String) -> Float? {
        guard let one = prints[first], let two = prints[second] else { return nil }
        return analyzer.distance((first, one), (second, two))
    }

    /// The fragment's preselected photos, as the AI would see them.
    func preselect(_ fragment: Fragment) -> [Preselected] {
        Preselector.select(fragment, analyses: analyses, library: library, distance: distance)
    }

    static func make(_ deps: TriggerDependencies, report: (TriggerProgress) async -> Void) async -> TriggerRanking {
        await make(library: deps.library, analyzer: deps.analyzer, analyses: deps.analyses, now: deps.now(),
                   calendar: deps.calendar, threshold: nil, groupingReport: deps.groupingReport, report: report)
    }

    // swiftlint:disable:next function_parameter_count
    static func make(library reader: PhotoLibraryReading, analyzer: PhotoAnalyzing, analyses store: AnalysisStore,
                     now: Date, calendar: Calendar, threshold stored: ThresholdResult?,
                     groupingReport: (@Sendable (Data) -> Void)?,
                     report: (TriggerProgress) async -> Void) async -> TriggerRanking {
        let since = { (days: Double) in now.addingTimeInterval(-days * 86_400) }
        let eligible = await reader.assets(since: since(placeDays), knownFilenames: store.filenames())
            .filter { LibraryFilter.eligible($0, now: now) }
        let recent = eligible.filter { ($0.takenAt ?? .distantPast) >= since(groupingDays) }
        let all = await analyze(recent, analyzer: analyzer, store: store, now: now, report: report)
        let analyses = all.filter { !$0.value.isUtility }
        let utility = Set(all.filter(\.value.isUtility).keys)

        let threshold = stored ?? {
            let gapDates = eligible.filter { !utility.contains($0.id) }.compactMap(\.takenAt)
                .filter { $0 >= since(thresholdDays) }
            return PersonalThreshold.compute(gaps: PersonalThreshold.gaps(between: gapDates))
        }()
        // A photo without an analysis (unreadable, failed) sits this run out:
        // it would be grouped, ranked and sent as if it were clean.
        let groupable = recent.filter { analyses[$0.id] != nil }.compactMap { asset in
            asset.takenAt.map {
                GroupablePhoto(id: asset.id, takenAt: $0, location: asset.location, burstId: asset.burstId)
            }
        }
        let library = Dictionary(eligible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let prints = analyses.compactMapValues(\.featurePrint)
        let distance = { (first: String, second: String) -> Float? in
            guard let one = prints[first], let two = prints[second] else { return nil }
            return analyzer.distance((first, one), (second, two))
        }
        let grouping = FragmentGrouper.group(groupable, threshold: threshold, calendar: calendar, distance: distance)
        let past = eligible.compactMap { asset -> (day: String, point: GeoPoint)? in
            guard let point = asset.location, let date = asset.takenAt else { return nil }
            return (FragmentGrouper.belongsTo(date, calendar: calendar), point)
        }
        var scores: [String: FragmentScore] = [:]
        for fragment in grouping.fragments {
            scores[ComposeMeta.groupKey(fragment)] = FragmentScorer.score(
                fragment, analyses: analyses, library: library, at: now, calendar: calendar, pastLocations: past,
                bucket: FragmentScorer.bucket(of: fragment, analyses: analyses), multiplier: 1.0)
        }
        if let sink = groupingReport,
           let data = GroupingReport.make(grouping, scores: scores, library: library, utility: Array(utility),
                                          calendar: calendar) {
            sink(data)
        }
        let scored = grouping.fragments.compactMap { fragment -> (Fragment, FragmentScore)? in
            guard let score = scores[ComposeMeta.groupKey(fragment)], score.pushable else { return nil }
            return (fragment, score)
        }
        let groups = scored.sorted { $0.1.total > $1.1.total }.enumerated().map {
            RankedGroup(rank: $0.offset + 1, fragment: $0.element.0, score: $0.element.1)
        }
        let recentIds = groupable.sorted { $0.takenAt > $1.takenAt }.map(\.id)
        return TriggerRanking(groups: groups, fragments: grouping.fragments, analyses: analyses, library: library,
                              prints: prints, analyzer: analyzer, utility: utility.sorted(), recentIds: recentIds,
                              pastLocations: past, threshold: threshold)
    }

    /// Every recent photo's analysis: saved ones from disk, the rest
    /// analysed now and saved one by one, so an interrupted run resumes.
    /// A photo that fails is written down and left alone for a day.
    private static func analyze(_ assets: [LibraryAsset], analyzer: PhotoAnalyzing, store: AnalysisStore, now: Date,
                                report: (TriggerProgress) async -> Void) async -> [String: PhotoAnalysis] {
        let saved = store.analyzedIds()
        var failures = store.failures()
        var results: [String: PhotoAnalysis] = [:]
        var todo: [String] = []
        var waiting = 0
        for asset in assets {
            if saved.contains(asset.id), let analysis = store.load(asset.id) {
                results[asset.id] = analysis
            } else if let failed = failures[asset.id], (0..<retryAfter).contains(now.timeIntervalSince(failed)) {
                waiting += 1
            } else {
                todo.append(asset.id)
            }
        }
        var done = results.count + waiting
        await report(.analyzing(done: done, total: assets.count))
        let names = Dictionary(assets.map { ($0.id, $0.originalFilename) }, uniquingKeysWith: { first, _ in first })
        var unsaved = 0
        for id in todo {
            if let analysis = await analyzer.analyze(id) {
                // The file name goes with it: later presses need not ask PhotoKit.
                let named = analysis.with(originalFilename: names[id] ?? nil)
                try? store.save(named)
                results[id] = named
                if failures.removeValue(forKey: id) != nil { unsaved += 1 }
            } else {
                failures[id] = now
                unsaved += 1
            }
            if unsaved >= failuresBatch {
                try? store.saveFailures(failures)
                unsaved = 0
            }
            done += 1
            await report(.analyzing(done: done, total: assets.count))
        }
        if unsaved > 0 { try? store.saveFailures(failures) }
        return results
    }
}
