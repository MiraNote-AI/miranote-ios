import Foundation

/// Everything the scheduler talks to, injectable for tests.
public struct SchedulerDependencies: Sendable {
    public var library: PhotoLibraryReading
    public var analyzer: PhotoAnalyzing
    public var places: PlaceNaming
    public var client: ComposeClient
    public var notifications: PushNotificationCenter
    public var analyses: AnalysisStore
    public var records: PushRecordStore
    public var ledger: PushLedgerStore
    public var preferences: PushPreferencesStore
    public var cache: AIResultCache
    public var log: ScheduleLogStore
    public var state: SchedulerStateStore
    public var lastRun: LastRunStore
    /// The calendar of the zone the phone is in now, read at each run.
    public var calendar: @Sendable () -> Calendar
    public var now: @Sendable () -> Date
    public var sleep: @Sendable (TimeInterval) async throws -> Void
    /// The fake-AI switch, read at each run and press.
    public var fakeAI: @Sendable () -> Bool
    /// zh-Hans catalog lookup for content (`TriggerContentKey`).
    public var zh: @Sendable (String) -> String
    /// Receives each run's grouping as JSON (`GroupingReport`); nil keeps none.
    public var groupingReport: (@Sendable (Data) -> Void)?

    public init(
        library: PhotoLibraryReading, analyzer: PhotoAnalyzing, places: PlaceNaming, client: ComposeClient,
        notifications: PushNotificationCenter,
        analyses: AnalysisStore = AnalysisStore(directory: AnalysisStore.defaultDirectory),
        records: PushRecordStore = PushRecordStore(directory: PushRecordStore.defaultDirectory),
        ledger: PushLedgerStore = PushLedgerStore(file: PushLedgerStore.defaultFile),
        preferences: PushPreferencesStore = PushPreferencesStore(file: PushPreferencesStore.defaultFile),
        cache: AIResultCache = AIResultCache(file: AIResultCache.defaultFile),
        log: ScheduleLogStore = ScheduleLogStore(file: ScheduleLogStore.defaultFile),
        state: SchedulerStateStore = SchedulerStateStore(file: SchedulerStateStore.defaultFile),
        lastRun: LastRunStore = LastRunStore(file: LastRunStore.defaultFile),
        calendar: @escaping @Sendable () -> Calendar = { Calendar.current },
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        fakeAI: @escaping @Sendable () -> Bool, zh: @escaping @Sendable (String) -> String,
        groupingReport: (@Sendable (Data) -> Void)? = nil
    ) {
        self.library = library
        self.analyzer = analyzer
        self.places = places
        self.client = client
        self.notifications = notifications
        self.analyses = analyses
        self.records = records
        self.ledger = ledger
        self.preferences = preferences
        self.cache = cache
        self.log = log
        self.state = state
        self.lastRun = lastRun
        self.calendar = calendar
        self.now = now
        self.sleep = sleep
        self.fakeAI = fakeAI
        self.zh = zh
        self.groupingReport = groupingReport
    }
}

/// Plans the next seven evenings each time the app comes to the front
/// (handoff 4): reconcile the ledger, analyse new photos, regroup 60 days,
/// rank per slot, lay the nights out, send the groups that need the AI all
/// at once, schedule each night as its answer comes back, keep the log.
///
/// One run at a time: a run asked for while one runs is folded into one
/// rerun after it.
public actor PushScheduler {
    /// Why a run started (`ScheduleRun.trigger`).
    public enum Trigger: String, Sendable {
        case foreground, menu, replan, timeZone, clearAll, copyUpgrade, fakeAIOff
    }

    /// A full run from the front at most this often.
    public static let fullRunInterval: TimeInterval = 3600
    /// Batch poll interval of a scheduling run.
    public static let pollInterval: TimeInterval = 15
    /// A backend job is kept this long; an older one is submitted again.
    public static let jobLifetime: TimeInterval = 3600
    /// Debug pushes go out this far ahead.
    public static let debugDelay: TimeInterval = 10

    let deps: SchedulerDependencies
    public private(set) var isRunning = false
    var pendingRerun: Trigger?
    /// The run in progress.
    var work = RunWork()
    /// Bumped by `clearAll`: a run of an older generation stops writing.
    var generation = 0
    /// The generation the run in progress started in.
    var runGeneration = 0
    /// Set by `turnOff`: no run starts, whoever asks, until `turnOn`.
    public internal(set) var isOff = false
    /// The current run's uploads, cancelled by `turnOff`.
    var wave: Task<[(AIAsk, AISent)], Never>?
    var inBackground = false
    /// The newest scene-phase change heard (`appBecameActive` /
    /// `appEnteredBackground` `sequence`): an older one arriving late is stale.
    var phaseSequence = 0
    var outsideCursor: Int?
    var outsidePressing = false
    /// The generation the current "try outside" press started in.
    var outsideGeneration = 0
    /// The current press, cancelled by `turnOff`.
    var press: Task<Void, Never>?
    var lastReport: LastRunReport?
    var lastRanking: TriggerRanking?
    /// Notifications being added whose ledger row is not written yet: not
    /// orphans to `reconcile`.
    var adding: Set<String> = []

    public init(_ dependencies: SchedulerDependencies) {
        deps = dependencies
    }

    // MARK: Gate

    /// The app came to the front: run unless a full run finished within
    /// the hour -- except when the last run left nights unfilled, the time
    /// zone changed (then every scheduled push is taken back first), the
    /// copy rules changed since the pushes were written (then those not yet
    /// locked are, once), or the fake AI is off and wrote some of them (then
    /// those not yet locked are).
    /// `sequence` orders it against `appEnteredBackground`: a call older than
    /// the last phase change heard does nothing (nil: always current).
    public func appBecameActive(sequence: Int? = nil) async {
        guard isCurrentPhase(sequence) else { return }
        if inBackground { restartBudgets() }
        inBackground = false
        let state = deps.state.load()
        let upgraded = state.copyVersion != TriggerMemory.copyVersion ? await takeBackOlderCopy() : false
        let unfaked = deps.fakeAI() ? false : await takeBackFakeCopy()
        let zone = deps.calendar().timeZone.identifier
        if let old = state.timeZoneId, old != zone {
            // A run still planning in the old zone stops writing, as after `clearAll`.
            generation += 1
            // Recorded at once, so it happens once; killed before the run ends, the next return still runs.
            try? deps.state.update {
                $0.timeZoneId = zone
                $0.lastRunLeftDaysUnfilled = true
            }
            await removeActive(.timeZone) { _ in true }
            return await request(.timeZone)
        }
        if upgraded { return await request(.copyUpgrade) }
        if unfaked { return await request(.fakeAIOff) }
        guard gateOpen(state) else { return }
        await request(.foreground)
    }

    /// The first time the app comes to the front under new copy rules: the
    /// pushes written under the old ones that are not yet locked are taken
    /// back, so the run that follows composes them again (their cache
    /// entries no longer match, `AIResultCache.key`). Recorded at once, so
    /// it happens once. True when any push was taken back.
    func takeBackOlderCopy() async -> Bool {
        let now = deps.now()
        let older = Set(deps.ledger.load()
            .filter { $0.isActive && $0.scheduledFor.timeIntervalSince(now) > SchedulePlanner.lockWindow }
            .map(\.pushId))
        try? deps.state.update {
            $0.copyVersion = TriggerMemory.copyVersion
            // Killed before the run ends: the next return still runs.
            if !older.isEmpty { $0.lastRunLeftDaysUnfilled = true }
        }
        guard !older.isEmpty else { return false }
        await removeActive(.copyUpgrade) { older.contains($0.pushId) }
        return true
    }

    /// Records `sequence` as the newest phase change; false when a newer one
    /// was heard already.
    func isCurrentPhase(_ sequence: Int?) -> Bool {
        guard let sequence else { return true }
        guard sequence > phaseSequence else { return false }
        phaseSequence = sequence
        return true
    }

    func gateOpen(_ state: SchedulerState) -> Bool {
        guard let last = state.lastFullRunAt, !state.lastRunLeftDaysUnfilled else { return true }
        return deps.now().timeIntervalSince(last) >= Self.fullRunInterval
    }

    /// Runs now, or once more after the run in progress. Turned off: nothing.
    func request(_ trigger: Trigger) async {
        guard !isOff else { return }
        guard !isRunning else {
            // A forced rerun beats a gated one.
            if pendingRerun == nil || pendingRerun == .foreground { pendingRerun = trigger }
            return
        }
        isRunning = true
        var next: Trigger? = trigger
        while let current = next {
            await runOnce(current)
            next = pendingRerun
            pendingRerun = nil
            if next == .foreground, !gateOpen(deps.state.load()) { next = nil }
        }
        isRunning = false
    }

    // MARK: The run

    func runOnce(_ trigger: Trigger) async {
        let mine = generation
        runGeneration = mine
        let started = deps.now()
        let calendar = deps.calendar()
        work = RunWork()
        var run = ScheduleRun(startedAt: started, finishedAt: started, trigger: trigger.rawValue)
        // The zone this run plans in: a change from it is caught even before the first run ends.
        try? deps.state.update { $0.timeZoneId = calendar.timeZone.identifier }
        let allowed = await deps.notifications.isAllowed()
        await reconcile(allowed: allowed)
        guard mine == generation else { return }
        // A job older than the backend keeps it is gone: submit again if needed.
        try? deps.state.update {
            $0.outstanding = $0.outstanding.filter {
                started.timeIntervalSince($0.value.submittedAt) < Self.jobLifetime
            }
        }
        let slots = PushSlots.make(now: started, calendar: calendar)
        let refusal: String? = await deps.library.requestAccess() == .denied ? "photosDenied"
            : allowed ? nil : "notificationsOff"
        guard mine == generation else { return }
        if let refusal {
            run.error = refusal
            run.emptyDays = Dictionary(uniqueKeysWithValues: slots.map {
                (SchedulePlanner.day($0, calendar: calendar), refusal)
            })
            return finish(run, generation: mine, calendar: calendar, unfilled: true)
        }
        let ranking = await rank(now: started, calendar: calendar)
        guard mine == generation else { return }
        lastRanking = ranking
        await dropDisallowed()
        let context = plan(ranking, slots: slots, calendar: calendar, generation: mine)
        run.fragments = ranking.fragments.count
        run.candidates = context.candidateCount
        await walk(context)
        guard mine == generation else { return }
        run.groups = work.outcomes
        run.aiSent = work.aiSent
        run.questionClashes = work.questionClashes
        for day in work.days {
            switch day.state {
            case .scheduled, .kept: run.scheduledDays.append(day.plan.slotDay)
            case .empty(let reason): run.emptyDays[day.plan.slotDay] = reason
            default: run.emptyDays[day.plan.slotDay] = "aiError"
            }
        }
        let unfilled = run.emptyDays.values.contains { $0 == "aiError" || $0 == "leftBeforeResult" }
        saveReport(context, emptyDays: run.emptyDays, calendar: calendar)
        finish(run, generation: mine, calendar: calendar, unfilled: unfilled)
    }

    private func finish(_ run: ScheduleRun, generation mine: Int, calendar: Calendar, unfilled: Bool) {
        guard mine == generation else { return }
        var run = run
        run.finishedAt = deps.now()
        try? deps.log.append(run)
        // Counted when the background time ran out (iOS may end the app then); the
        // nights scheduled after all, the process having lived, no longer count.
        let stillLeft = run.emptyDays.values.filter { $0 == "leftBeforeResult" }.count
        if work.leftDays.count > stillLeft { try? deps.log.bumpLeftBeforeResult(by: stillLeft - work.leftDays.count) }
        try? deps.state.update {
            $0.lastFullRunAt = run.startedAt
            $0.lastRunLeftDaysUnfilled = unfilled
            $0.timeZoneId = calendar.timeZone.identifier
        }
    }

    /// Analyses new photos and regroups, with the stored T unless it is a
    /// week old (then it is computed again and stored).
    func rank(now: Date, calendar: Calendar, report: (TriggerProgress) async -> Void = { _ in }) async
        -> TriggerRanking {
        let mine = generation
        let state = deps.state.load()
        let stale = state.needsThreshold(now: now)
        let ranking = await TriggerRanking.make(
            library: deps.library, analyzer: deps.analyzer, analyses: deps.analyses, now: now, calendar: calendar,
            threshold: stale ? nil : state.threshold, groupingReport: deps.groupingReport, report: report)
        if stale, mine == generation {
            try? deps.state.update {
                $0.threshold = ranking.threshold
                $0.thresholdComputedAt = now
            }
        }
        return ranking
    }

    // MARK: Planning

    /// Ranks every fragment for every slot and lays the nights out.
    func plan(_ ranking: TriggerRanking, slots: [Date], calendar: Calendar, generation: Int) -> RunContext {
        let now = deps.now()
        try? deps.cache.purge(today: FragmentGrouper.belongsTo(now, calendar: calendar))
        let preferences = deps.preferences.load()
        let entries = deps.ledger.load()
        let pushed = LedgerReconciler.pushedDays(entries)
        let pushedPhotos = LedgerReconciler.pushedPhotos(entries)
        let verdicts = deps.cache.verdicts()
        var picks: [String: [Preselected]] = [:]
        for fragment in ranking.fragments { picks[ComposeMeta.groupKey(fragment)] = ranking.preselect(fragment) }
        var bySlot: [Date: [PushCandidate]] = [:]
        for slot in slots {
            bySlot[slot] = PushCandidates.ranked(
                ranking.fragments, aiPhotoIds: { (picks[ComposeMeta.groupKey($0)] ?? []).map(\.id) }, at: slot,
                analyses: ranking.analyses, library: ranking.library, calendar: calendar,
                pastLocations: ranking.pastLocations, pushedDays: pushed, pushedPhotos: pushedPhotos,
                preferences: preferences, cache: { verdicts[$0] })
        }
        let lastBucket = entries.filter { $0.deliveredAt != nil && !$0.isDebug }
            .max { ($0.deliveredAt ?? .distantPast) < ($1.deliveredAt ?? .distantPast) }?.bucket
        let plans = SchedulePlanner.plan(slots: slots, rankedFor: { bySlot[$0] ?? [] },
                                         active: entries.filter(\.isActive), lastDeliveredBucket: lastBucket,
                                         now: now, calendar: calendar)
        work.verdicts = verdicts
        work.days = plans.map(DayWork.init)
        let candidates = Set(bySlot.values.flatMap { $0.map(\.groupKey) }).count
        return RunContext(ranking: ranking, picks: picks, calendar: calendar, generation: generation,
                          candidateCount: candidates, preferences: preferences, pushedDays: pushed,
                          pushedPhotos: pushedPhotos, firstSlot: slots.first ?? now)
    }

    /// Keeps the debug page's view of this run, in memory and on disk.
    func saveReport(_ context: RunContext, emptyDays: [String: String], calendar: Calendar) {
        let ranking = context.ranking
        let fragments = ranking.fragments.map { fragment -> FragmentReport in
            let key = ComposeMeta.groupKey(fragment)
            let ids = (context.picks[key] ?? []).map(\.id)
            let bucket = FragmentScorer.bucket(of: fragment, analyses: ranking.analyses)
            let slot = context.firstSlot
            let verdicts = work.verdicts
            let result = PushCandidates.evaluate(
                fragment, bucket: bucket, aiPhotoIds: ids, at: slot, analyses: ranking.analyses,
                library: ranking.library, calendar: calendar, pastLocations: ranking.pastLocations,
                pushedDays: context.pushedDays, pushedPhotos: context.pushedPhotos, preferences: context.preferences,
                cache: { verdicts[$0] })
            let score = FragmentScorer.score(
                fragment, analyses: ranking.analyses, library: ranking.library, at: slot, calendar: calendar,
                pastLocations: ranking.pastLocations, bucket: bucket,
                multiplier: context.preferences.multiplier(for: bucket, at: slot) ?? 1.0)
            var ineligible: Ineligible?
            if case .failure(let reason) = result { ineligible = reason }
            return FragmentReport(groupKey: key, belongsTo: fragment.belongsTo, photoIds: fragment.photos.map(\.id),
                                  rawCount: fragment.photos.count, uniqueCount: fragment.uniqueCount, score: score,
                                  bucket: bucket, ineligible: ineligible, cacheKey: AIResultCache.key(ids))
        }
        let report = LastRunReport(
            finishedAt: deps.now(), emptyDays: emptyDays, fragments: fragments, utility: ranking.utility,
            categories: CategoryReport.make(ids: ranking.recentIds, analyses: ranking.analyses),
            threshold: ranking.threshold)
        lastReport = report
        try? deps.lastRun.save(report)
    }
}
