import Foundation

extension PushScheduler {
    // MARK: The story's "..." menu

    /// Applies the menu's choice: "not this day" blocks the push's
    /// belongs-to day for good, "fewer like this" cools its bucket down
    /// (never `other`). The pushes it rules out are taken back at once and
    /// the nights refilled. Debug pushes count too. A record saved before
    /// phase 2 (no ledger row, no bucket or day of its own) takes its day
    /// from the memory's date; "fewer" needs a bucket and does nothing then.
    /// `replan` false (an install that may not schedule, decision 8) does
    /// all of that but leaves the nights unfilled: no run, no upload.
    public func menu(_ action: MenuAction, pushId: String, replan: Bool = true) async {
        let entry = deps.ledger.load().first { $0.pushId == pushId }
        let record = deps.records.load(pushId)
        let day = entry?.belongsTo ?? record?.belongsTo ?? record.flatMap { Self.dayKey($0.memory.date) }
        let bucket = entry?.bucket ?? record?.bucketId
        // The day key is a local date: the photos keep the block across a time-zone change.
        let photos = entry?.photoIds ?? record.map { $0.photoIds.values.sorted() } ?? []
        let now = deps.now()
        switch action {
        case .notThisDay:
            guard let day else { return }
            try? deps.preferences.update {
                $0.blockedDays[day] = now
                if !photos.isEmpty { $0.blockedPhotos[day] = photos }
            }
        case .fewerLikeThis:
            guard let bucket, bucket != .other else { return }
            try? deps.preferences.update { $0.fewer[bucket] = now }
        }
        try? deps.ledger.update(pushId) {
            $0.menuAction = action
            $0.menuActionAt = now
        }
        switch action {
        case .notThisDay:
            await removeActive(.menuDay) { $0.belongsTo == day || !Set($0.photoIds).isDisjoint(with: photos) }
        case .fewerLikeThis: await removeActive(.menuBucket) { $0.bucket == bucket }
        }
        guard replan else { return }
        await request(.menu)
    }

    /// An App Store install (decision 8), or a TestFlight tester who turned
    /// the trigger off: no run starts until `turnOn`, whoever asks; a run in
    /// flight stops writing, as after `clearAll`, its uploads not yet sent
    /// are cancelled, and no rerun follows it. Every push of ours is taken
    /// back -- scheduled ones marked in the ledger with `reason` -- and
    /// delivered ones leave Notification Center, so none can open a story.
    public func turnOff(_ reason: RemovalReason) async {
        isOff = true
        generation += 1
        pendingRerun = nil
        wave?.cancel()
        press?.cancel()
        // Turned on again within the hour, the next return still plans. No
        // run yet: nothing to write (the hourly gate is open anyway).
        let state = deps.state.load()
        if state.lastFullRunAt != nil, !state.lastRunLeftDaysUnfilled {
            try? deps.state.update { $0.lastRunLeftDaysUnfilled = true }
        }
        let known = Set(deps.ledger.load().map(\.identifier).filter(PushIdentifier.isOurs))
        await removeActive(reason) { _ in true }
        let pending = await deps.notifications.pending().filter(PushIdentifier.isOurs)
        if !pending.isEmpty { await deps.notifications.removePending(pending.sorted()) }
        let ours = known.union(pending)
        if !ours.isEmpty { await deps.notifications.removeDelivered(ours.sorted()) }
    }

    /// The tester turned the trigger on again: runs may start.
    public func turnOn() {
        isOff = false
    }

    /// `text` when it is a "yyyy-MM-dd" day (the memory's `date`), else nil.
    static func dayKey(_ text: String) -> String? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.map(\.count) == [4, 2, 2],
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
        return text
    }

    // MARK: What the user did with a push (ledger only: no learning)

    /// An opened push was delivered, whatever the next reconcile would say.
    public func markOpened(_ pushId: String) {
        stamp(pushId) { entry, now in
            entry.openedAt = entry.openedAt ?? now
            if entry.deliveredAt == nil, entry.removedAt == nil {
                entry.deliveredAt = min(entry.scheduledFor, now)
                entry.notDeliveredReason = nil
            }
        }
    }

    public func markStoryFinished(_ pushId: String) {
        stamp(pushId) { $0.storyFinishedAt = $0.storyFinishedAt ?? $1 }
    }

    public func markMadePage(_ pushId: String) {
        stamp(pushId) { $0.madePageAt = $0.madePageAt ?? $1 }
    }

    /// Every ledger row, oldest first (testers' views and UI-test probes).
    public func ledgerEntries() -> [LedgerEntry] {
        deps.ledger.load()
    }

    private func stamp(_ pushId: String, _ change: (inout LedgerEntry, Date) -> Void) {
        let now = deps.now()
        try? deps.ledger.update(pushId) { change(&$0, now) }
    }

    // MARK: Leaving the app

    /// `sequence` as in `appBecameActive`: a background call that lands
    /// after a newer return to the front is ignored.
    public func appEnteredBackground(sequence: Int? = nil) {
        guard isCurrentPhase(sequence) else { return }
        inBackground = true
    }

    /// iOS is about to suspend the app: every night whose job is still out
    /// counts as "left before the result" (decision 7) and the next return
    /// to the front runs again. The run is not cancelled: if the process
    /// lives, polling resumes on return, and a night scheduled after all
    /// stops counting when the run ends.
    public func backgroundTimeExpired() async {
        // A run cleared while suspended writes nothing into the cleared stores.
        guard isRunning, runGeneration == generation else { return }
        let out = work.days.indices.filter { work.days[$0].isWaiting && !work.leftDays.contains($0) }
        guard !out.isEmpty else { return }
        for index in out {
            work.leftDays.insert(index)
            switch work.days[index].state {
            case .waiting(let job): log(index, job.candidate, .left, since: job.startedAt)
            case .asking(let candidate): log(index, candidate, .left, since: deps.now())
            default: break
            }
        }
        try? deps.log.bumpLeftBeforeResult(by: out.count)
        try? deps.state.update { $0.lastRunLeftDaysUnfilled = true }
    }
}
