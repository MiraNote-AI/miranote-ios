import Foundation

extension PushScheduler {
    // MARK: The story's "..." menu

    /// Applies the menu's choice: "not this day" blocks the push's
    /// belongs-to day for good, "fewer like this" cools its bucket down
    /// (never `other`). The pushes it rules out are taken back at once and
    /// the nights refilled. Debug pushes count too.
    public func menu(_ action: MenuAction, pushId: String) async {
        let entry = deps.ledger.load().first { $0.pushId == pushId }
        let record = deps.records.load(pushId)
        guard let day = entry?.belongsTo ?? record?.belongsTo,
              let bucket = entry?.bucket ?? record?.bucketId else { return }
        if action == .fewerLikeThis, bucket == .other { return }
        let now = deps.now()
        try? deps.preferences.update { preferences in
            switch action {
            case .notThisDay: preferences.blockedDays[day] = now
            case .fewerLikeThis: preferences.fewer[bucket] = now
            }
        }
        try? deps.ledger.update(pushId) {
            $0.menuAction = action
            $0.menuActionAt = now
        }
        switch action {
        case .notThisDay: await removeActive(.menuDay) { $0.belongsTo == day }
        case .fewerLikeThis: await removeActive(.menuBucket) { $0.bucket == bucket }
        }
        await request(.menu)
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

    public func appEnteredBackground() {
        inBackground = true
    }

    /// iOS is about to suspend the app: every night whose job is still out
    /// counts as "left before the result" (decision 7) and the next return
    /// to the front runs again. The run is not cancelled: if the process
    /// lives, polling resumes on return.
    public func backgroundTimeExpired() async {
        guard isRunning else { return }
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
