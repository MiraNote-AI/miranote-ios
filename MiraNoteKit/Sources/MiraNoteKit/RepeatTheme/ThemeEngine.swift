import Foundation

/// Everything a theme run talks to, injectable for tests.
public struct ThemeDependencies: Sendable {
    public static let defaultMomentsCap = 5000

    public var library: PhotoLibraryReading
    public var analyzer: PhotoAnalyzing
    /// V1's per-photo analyses: the shared checkup fills them for the
    /// photos V1 groups (its last 61 days), so V1 does not read them again.
    public var analyses: AnalysisStore
    public var photos: ThemePhotoStore
    public var themes: ThemeLibrary
    public var rounds: RoundLog
    public var window: ThemeWindowStore
    /// `themes/runs.json`.
    public var runs: ThemeRunLog
    public var client: ThemeRoundClient
    /// A photo's bytes for a round image (any size; prepared to 336 px).
    public var imageData: @Sendable (String) async -> Data?
    public var now: @Sendable () -> Date
    public var calendar: Calendar
    /// At most this many moments are clustered: the newest (spec 6.2, I2).
    public var momentsCap: Int

    public init(library: PhotoLibraryReading, analyzer: PhotoAnalyzing, analyses: AnalysisStore,
                photos: ThemePhotoStore, themes: ThemeLibrary, rounds: RoundLog, window: ThemeWindowStore,
                runs: ThemeRunLog, client: ThemeRoundClient, imageData: @escaping @Sendable (String) async -> Data?,
                now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current,
                momentsCap: Int = ThemeDependencies.defaultMomentsCap) {
        self.library = library
        self.analyzer = analyzer
        self.analyses = analyses
        self.photos = photos
        self.themes = themes
        self.rounds = rounds
        self.window = window
        self.runs = runs
        self.client = client
        self.imageData = imageData
        self.now = now
        self.calendar = calendar
        self.momentsCap = momentsCap
    }
}

/// Finds the repeat themes (spec section 4, steps 1-6): checkup, moments,
/// piles, claim, round-1 asks, library. One run at a time: a run asked for
/// while one is in flight waits for it and then runs once more, and every
/// caller that waited meanwhile shares that one follow-up (it runs with the
/// first waiting caller's trigger and deadline, and they all get its report).
/// `stopEarly` ends the runs already asked for as if at their deadline.
public actor ThemeEngine {
    /// Clustering waits until the checkup has gone this far back (A2).
    static let clusterAfterDays = 60
    /// The checkup stops this long before the run's deadline, leaving the
    /// time to cluster and ask (so a cut-short checkup that got 60 days
    /// back can still find piles the same run).
    static let clusterReserve: TimeInterval = 60

    let deps: ThemeDependencies
    /// Bumped by `stopEarly`; read off the actor by a run's clock.
    let stops = StopCount()
    private var active: Task<ThemeRunReport, Never>?
    private var queued: Task<ThemeRunReport, Never>?
    /// Callers waiting on a follow-up run (for tests).
    private(set) var waitingCallers = 0
    /// Photos whose checkup gave no theme vision (a simulator): not read
    /// again for a theme record while this engine lives. Kept in memory
    /// only, so a new process tries them once more.
    private var noVision = Set<String>()
    private var lastPiles: [Pile] = []
    private var lastFollows: [String: Int] = [:]

    public init(_ deps: ThemeDependencies) {
        self.deps = deps
    }

    public func run(trigger: ThemeTrigger, deadline: Date?) async -> ThemeRunReport {
        let mark = stops.value
        if let queued {
            waitingCallers += 1
            defer { waitingCallers -= 1 }
            return await queued.value
        }
        if let active {
            waitingCallers += 1
            defer { waitingCallers -= 1 }
            let task = Task {
                _ = await active.value
                return await self.runQueued(trigger: trigger, deadline: deadline, mark: mark)
            }
            queued = task
            return await task.value
        }
        let task = Task { await self.runActive(trigger: trigger, deadline: deadline, mark: mark) }
        active = task
        return await task.value
    }

    private func runActive(trigger: ThemeTrigger, deadline: Date?, mark: Int) async -> ThemeRunReport {
        let report = await perform(trigger: trigger, deadline: deadline, mark: mark)
        active = nil
        return report
    }

    private func runQueued(trigger: ThemeTrigger, deadline: Date?, mark: Int) async -> ThemeRunReport {
        active = queued
        queued = nil
        let report = await perform(trigger: trigger, deadline: deadline, mark: mark)
        active = nil
        return report
    }

    /// Reads every theme record (for the days): for the debug page, not a loop.
    public func snapshot() -> ThemeSnapshot {
        let rows = deps.themes.load()
        return ThemeSnapshot(runs: deps.runs.load(), piles: lastPiles, follows: lastFollows, themes: rows,
                             rounds: deps.rounds.load(),
                             days: ThemeSnapshot.days(of: rows, photos: deps.photos.loadAll(), calendar: deps.calendar))
    }

    /// Blocks a big or small theme (debug page, "Not this theme"): a blocked
    /// big theme is never asked about again. A blocked small theme's name
    /// still goes out among its big theme's old names on a re-ask, so the
    /// row keeps its id and stays blocked. Waits for a run in flight, so the
    /// run's save cannot undo it. A sensitive theme stays sensitive.
    public func block(_ themeId: String) async {
        await setStatus(themeId) { $0 == .sensitive ? nil : .blocked }
    }

    /// Clears a block; the next run sets frozen where it applies.
    public func unblock(_ themeId: String) async {
        await setStatus(themeId) { $0 == .blocked ? .active : nil }
    }

    private func setStatus(_ themeId: String, _ change: (ThemeStatus) -> ThemeStatus?) async {
        while let task = queued ?? active { _ = await task.value }
        var rows = deps.themes.load()
        guard let index = rows.firstIndex(where: { $0.id == themeId }),
              let status = change(rows[index].status) else { return }
        rows[index].status = status
        try? deps.themes.save(rows)
    }

    // MARK: - One run

    private func perform(trigger: ThemeTrigger, deadline asked: Date?, mark: Int) async -> ThemeRunReport {
        let now = deps.now()
        // No deadline is one never reached -- unless `stopEarly` was called
        // since the run was asked for: then every deadline has passed.
        let deadline = RunDeadline(date: asked ?? .distantFuture) { [stops, deps] in
            stops.value == mark ? deps.now() : .distantFuture
        }
        let calendar = deps.calendar
        var report = ThemeRunReport(at: now, trigger: trigger, photos: 0, checkedNew: 0, moments: 0, piles: [],
                                    checkupMs: 0, clusterMs: 0, peakMemoryMB: nil, asked: 0, failures: [])

        // 1. The window and the library in it.
        var window = windowAnchor(now: now)
        let saved = deps.analyses.loadAll()
        let fetched = await deps.library.assets(since: window.start,
                                                knownFilenames: saved.compactMapValues(\.originalFilename))
        report.photos = fetched.count
        // An empty fetch (access taken away, a PhotoKit error) is never read
        // as an empty library: nothing is pruned, nothing is asked.
        guard !fetched.isEmpty else {
            report.failures.append("The library gave no photos: nothing changed")
            return finish(report)
        }
        let ids = Set(fetched.map(\.id))
        // Under "Select Photos" a photo left out of the fetch may be hidden,
        // not deleted: nothing is pruned (a pruned record is read again, a
        // pruned sensitive or blocked pile is sent again once access is full).
        let limited = await deps.library.requestAccess() == .limited
        let rows = limited ? deps.themes.load() : prune(keeping: ids)

        // 2. The checkup, newest first.
        let checkupStart = ContinuousClock.now
        let checkup = await self.checkup(fetched, saved: saved, window: &window, now: now,
                                         deadline: deadline.earlier(by: Self.clusterReserve))
        report.checkupMs = Self.milliseconds(since: checkupStart)
        report.checkedNew = checkup.count
        let records = deps.photos.loadAll()
        if let stop = notReady(checkup.outcome, records: records, ids: ids, window: window, now: now) {
            report.failures.append(stop)
            return finish(report)
        }
        if deadline.reached {
            report.failures.append("Deadline reached before clustering")
            return finish(report)
        }

        // 3. Moments (the newest `momentsCap`), the tree, the piles.
        let clusterStart = ContinuousClock.now
        let themePhotos = records.values.filter { photo in
            photo.isTheme && ids.contains(photo.id) && photo.takenAt >= window.start
                && window.printRevision.map { photo.printRevision == $0 } ?? true
        }
        var moments = MomentBuilder.build(Array(themePhotos), calendar: calendar)
        if moments.count > deps.momentsCap { moments = Array(moments.suffix(max(0, deps.momentsCap))) }
        let piles = PileCutter.cut(moments, tree: ThemeTree.build(moments.map(\.vector)))
        report.clusterMs = Self.milliseconds(since: clusterStart)
        report.peakMemoryMB = ThemeRunReport.peakMemoryMB()
        report.moments = moments.count
        report.piles = piles

        let byId = Dictionary(moments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let scene = Scene(piles: piles, moments: byId, photos: records, calendar: calendar)
        await claimAndAsk(scene, rows: rows, deadline: deadline, report: &report)
        return finish(report)
    }

    /// Why the checkup is not far enough along to cluster on, or nil (A1,
    /// A2): it must have finished, or got 60 days back. And while records of
    /// an older print revision are left (the OS changed it and they are not
    /// all read again), only a finished checkup will do: clustering on the
    /// few re-read photos would freeze every old theme.
    private func notReady(_ outcome: CheckupOutcome, records: [String: ThemePhoto], ids: Set<String>,
                          window: ThemeWindow, now: Date) -> String? {
        guard !outcome.finished else { return nil }
        if let revision = window.printRevision,
           records.values.contains(where: { $0.printRevision != revision && ids.contains($0.id) }) {
            return "Print revision changed: re-reading older photos before piles"
        }
        let sixtyBack = deps.calendar.date(byAdding: .day, value: -Self.clusterAfterDays, to: now) ?? now
        guard let through = outcome.checkedThrough, through <= sixtyBack else {
            let days = outcome.checkedThrough.map { Int(now.timeIntervalSince($0) / 86_400) } ?? 0
            return "Checked \(days) days back so far: piles wait for \(Self.clusterAfterDays)"
        }
        return nil
    }

    /// Steps 4-6: old themes claim tonight's piles (the results go on the
    /// rows), then round 1 for new piles and grown themes only, while the
    /// deadline allows (the asks left are asked on the next run).
    private func claimAndAsk(_ scene: Scene, rows stored: [ThemeRow], deadline: RunDeadline,
                             report: inout ThemeRunReport) async {
        let inWindow = Set(scene.moments.values.flatMap(\.photoIds))
        let claim = ThemeClaim.claim(stored.filter { $0.kind == .big }, piles: scene.piles, moments: scene.moments,
                                     window: inWindow)
        var rows = Self.writeBack(claim, to: stored, moments: scene.moments, photos: scene.photos,
                                  calendar: scene.calendar)
        try? deps.themes.save(rows)
        lastPiles = scene.piles
        lastFollows = claim.follows

        let asks = Self.asks(claim, rows: rows, scene: scene)
        for (index, ask) in asks.enumerated() {
            if deadline.reached {
                report.failures.append("Deadline reached: \(asks.count - index) asks left")
                break
            }
            let outcome = await self.ask(ask, rows: rows, scene: scene)
            if outcome.sent { report.asked += 1 }
            if let failure = outcome.failure { report.failures.append(failure) }
            if let updated = outcome.rows {
                rows = updated
                try? deps.themes.save(rows)
            }
        }
    }

    /// Drops what the library no longer holds (the fetch is not empty):
    /// theme records, and photos on every theme list (D8). The library rows.
    private func prune(keeping ids: Set<String>) -> [ThemeRow] {
        try? deps.photos.prune(keeping: ids)
        let rows = deps.themes.load()
        let gone = Set(rows.flatMap(\.members)).subtracting(ids)
        guard !gone.isEmpty else { return rows }
        let kept = ThemeLibrary.removing(gone, from: rows)
        try? deps.themes.save(kept)
        return kept
    }

    /// The stored window, or (first run) a new one from today, kept.
    private func windowAnchor(now: Date) -> ThemeWindow {
        if let stored = deps.window.load() { return stored }
        let first = ThemeWindow.first(now: now, calendar: deps.calendar)
        try? deps.window.save(first)
        return first
    }

    private func finish(_ report: ThemeRunReport) -> ThemeRunReport {
        try? deps.runs.append(report)
        return report
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    // MARK: - Checkup

    /// One checkup pass over `assets` (`PhotoCheckupRunner`, newest first).
    /// A photo needs a theme record when it has none, or one of another
    /// print revision than the window's; an undated photo never does (it
    /// can have no record), nor one whose checkup gave no vision. When the
    /// pass meets a revision other than the window's (the OS changed it),
    /// the window takes it and a second pass reads every older record again
    /// (A1). That change is only seen once some photo is read.
    private func checkup(_ assets: [LibraryAsset], saved: [String: PhotoAnalysis], window: inout ThemeWindow,
                         now: Date, deadline: RunDeadline) async -> (outcome: CheckupOutcome, count: Int) {
        let watcher = CheckupWatcher(base: BoundedAnalyzer(base: deps.analyzer,
                                                           seconds: TriggerRanking.analysisTimeout))
        let undated = Set(assets.filter { $0.takenAt == nil }.map(\.id))
        // V1 groups its last 61 days; older analyses it would prune again.
        let v1Since = now.addingTimeInterval(-TriggerRanking.groupingDays * 86_400)
        let v1Wanted = Set(assets.filter { ($0.takenAt ?? .distantPast) >= v1Since && saved[$0.id] == nil }.map(\.id))
        var v1Done = Set<String>()
        var outcome: CheckupOutcome
        var passes = 0
        repeat {
            passes += 1
            let records = deps.photos.loadAll()
            let revision = window.printRevision
            let skipped = undated.union(noVision)
            outcome = await PhotoCheckupRunner.run(
                assets, needsV1: { v1Wanted.contains($0) && !v1Done.contains($0) },
                needsTheme: { id in
                    guard !skipped.contains(id) else { return false }
                    guard let record = records[id] else { return true }
                    return revision.map { record.printRevision != $0 } ?? false
                },
                analyzer: watcher, analyses: deps.analyses, themes: deps.photos, now: now, calendar: deps.calendar,
                deadline: deadline.date, clock: deadline.clock, report: { _ in })
            v1Done.formUnion(outcome.analyses.keys)
            noVision.formUnion(watcher.noVision)
            guard let seen = watcher.revision, seen != window.printRevision else { break }
            window.printRevision = seen
            try? deps.window.save(window)
        } while passes < 2 && outcome.finished
        return (outcome, watcher.count)
    }

    // MARK: - Claim results on the rows

    /// Tonight's claim on the rows: a big row takes its ratio, flag and list;
    /// a small row its rule's list within its big row's (`SubThemeRule`).
    /// Active and frozen rows go frozen or active with the claim (a small
    /// one with its big one); blocked, sensitive and retired stay as they are.
    static func writeBack(_ claim: ClaimResult, to rows: [ThemeRow], moments: [String: Moment],
                          photos: [String: ThemePhoto], calendar: Calendar) -> [ThemeRow] {
        let smallLists = SubThemeRule.membersTonight(of: rows.filter { $0.kind == .small }, claim: claim,
                                                     moments: moments, photosById: photos, calendar: calendar)
        return rows.map { original in
            var row = original
            let movable = row.status == .active || row.status == .frozen
            switch row.kind {
            case .big:
                row.followRatio = claim.ratios[row.id]
                row.flagged = claim.flagged.contains(row.id)
                row.members = claim.members[row.id] ?? row.members
                if movable { row.status = claim.frozen.contains(row.id) ? .frozen : .active }
            case .small:
                row.members = smallLists[row.id] ?? row.members
                if movable, let parent = row.parentId {
                    row.status = claim.frozen.contains(parent) ? .frozen : .active
                }
            }
            return row
        }
    }
}
