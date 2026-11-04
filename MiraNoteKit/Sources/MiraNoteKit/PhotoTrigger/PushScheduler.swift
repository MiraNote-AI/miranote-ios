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
        case foreground, menu, replan, timeZone, clearAll
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
    var inBackground = false
    var previewCount = 0
    var outsideCursor: Int?
    var outsidePressing = false
    var lastReport: LastRunReport?
    var lastRanking: TriggerRanking?

    public init(_ dependencies: SchedulerDependencies) {
        deps = dependencies
    }

    // MARK: Gate

    /// The app came to the front: run unless a full run finished within
    /// the hour -- except when the last run left nights unfilled, or the
    /// time zone changed (then every scheduled push is taken back first).
    public func appBecameActive() async {
        if inBackground { restartBudgets() }
        inBackground = false
        let state = deps.state.load()
        let zone = deps.calendar().timeZone.identifier
        if let old = state.timeZoneId, old != zone {
            await removeActive(.timeZone) { _ in true }
            return await request(.timeZone)
        }
        guard gateOpen(state) else { return }
        await request(.foreground)
    }

    func gateOpen(_ state: SchedulerState) -> Bool {
        guard let last = state.lastFullRunAt, !state.lastRunLeftDaysUnfilled else { return true }
        return deps.now().timeIntervalSince(last) >= Self.fullRunInterval
    }

    /// Runs now, or once more after the run in progress.
    func request(_ trigger: Trigger) async {
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
        let started = deps.now()
        let calendar = deps.calendar()
        work = RunWork()
        var run = ScheduleRun(startedAt: started, finishedAt: started, trigger: trigger.rawValue)
        let allowed = await deps.notifications.isAllowed()
        await reconcile(allowed: allowed)
        // A job older than the backend keeps it is gone: submit again if needed.
        try? deps.state.update {
            $0.outstanding = $0.outstanding.filter {
                started.timeIntervalSince($0.value.submittedAt) < Self.jobLifetime
            }
        }
        let slots = PushSlots.make(now: started, calendar: calendar)
        let refusal: String? = await deps.library.requestAccess() == .denied ? "photosDenied"
            : allowed ? nil : "notificationsOff"
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
        try? deps.state.update {
            $0.lastFullRunAt = run.startedAt
            $0.lastRunLeftDaysUnfilled = unfilled
            $0.timeZoneId = calendar.timeZone.identifier
        }
    }

    /// Settles the ledger with the notification center and clears pushes
    /// delivered and unopened for 48 h from the tray.
    func reconcile(allowed: Bool) async {
        let pending = await deps.notifications.pending()
        let settled = LedgerReconciler.reconcile(deps.ledger.load(), now: deps.now(), pending: pending,
                                                 notificationsAllowed: allowed)
        try? deps.ledger.save(settled.entries)
        let ours = settled.clearDelivered.filter(PushIdentifier.isOurs)
        if !ours.isEmpty { await deps.notifications.removeDelivered(ours) }
    }

    /// Analyses new photos and regroups, with the stored T unless it is a
    /// week old (then it is computed again and stored).
    func rank(now: Date, calendar: Calendar, report: (TriggerProgress) async -> Void = { _ in }) async
        -> TriggerRanking {
        let state = deps.state.load()
        let stale = state.needsThreshold(now: now)
        let ranking = await TriggerRanking.make(
            library: deps.library, analyzer: deps.analyzer, analyses: deps.analyses, now: now, calendar: calendar,
            threshold: stale ? nil : state.threshold, groupingReport: deps.groupingReport, report: report)
        if stale {
            try? deps.state.update {
                $0.threshold = ranking.threshold
                $0.thresholdComputedAt = now
            }
        }
        return ranking
    }

    /// Takes back scheduled pushes the preferences no longer allow (a day
    /// blocked, a bucket cooling down since they were scheduled).
    func dropDisallowed() async {
        let preferences = deps.preferences.load()
        await removeActive(.menuDay) { preferences.isBlocked($0.belongsTo) }
        await removeActive(.menuBucket) { preferences.multiplier(for: $0.bucket, at: $0.scheduledFor) == nil }
    }

    /// Takes back every active (non-debug) push `matching`: pending
    /// request removed, ledger row marked.
    func removeActive(_ reason: RemovalReason, matching: (LedgerEntry) -> Bool) async {
        let now = deps.now()
        var entries = deps.ledger.load()
        var identifiers: [String] = []
        for index in entries.indices where entries[index].isActive && matching(entries[index]) {
            entries[index].removedReason = reason
            entries[index].removedAt = now
            identifiers.append(entries[index].identifier)
        }
        guard !identifiers.isEmpty else { return }
        try? deps.ledger.save(entries)
        await deps.notifications.removePending(identifiers.filter(PushIdentifier.isOurs))
    }

    // MARK: Planning

    /// Ranks every fragment for every slot and lays the nights out.
    func plan(_ ranking: TriggerRanking, slots: [Date], calendar: Calendar, generation: Int) -> RunContext {
        let now = deps.now()
        try? deps.cache.purge(today: FragmentGrouper.belongsTo(now, calendar: calendar))
        let preferences = deps.preferences.load()
        let entries = deps.ledger.load()
        let pushed = LedgerReconciler.pushedDays(entries)
        let verdicts = deps.cache.verdicts()
        var picks: [String: [Preselected]] = [:]
        for fragment in ranking.fragments { picks[ComposeMeta.groupKey(fragment)] = ranking.preselect(fragment) }
        var bySlot: [Date: [PushCandidate]] = [:]
        for slot in slots {
            bySlot[slot] = PushCandidates.ranked(
                ranking.fragments, aiPhotoIds: { (picks[ComposeMeta.groupKey($0)] ?? []).map(\.id) }, at: slot,
                analyses: ranking.analyses, library: ranking.library, calendar: calendar,
                pastLocations: ranking.pastLocations, pushedDays: pushed, preferences: preferences,
                cache: { verdicts[$0] })
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
                          firstSlot: slots.first ?? now)
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
                pushedDays: context.pushedDays, preferences: context.preferences, cache: { verdicts[$0] })
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
