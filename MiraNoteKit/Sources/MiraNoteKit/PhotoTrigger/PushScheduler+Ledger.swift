import Foundation

/// Settling the ledger with the notification center, and taking pushes back.
extension PushScheduler {
    /// Settles the ledger with the notification center, clears pushes
    /// delivered and unopened for 48 h from the tray, and takes back a
    /// pending request of ours the ledger does not hold (added right before
    /// the app was killed, before its row was written; or taken back in the
    /// ledger only). Other features' requests are never touched.
    func reconcile(allowed: Bool) async {
        let mine = generation
        let pending = await deps.notifications.pending()
        // Cleared meanwhile: the empty ledger stays empty.
        guard mine == generation else { return }
        let settled = LedgerReconciler.reconcile(deps.ledger.load(), now: deps.now(), pending: pending,
                                                 notificationsAllowed: allowed)
        try? deps.ledger.save(settled.entries)
        let held = Set(settled.entries.filter { $0.removedAt == nil && $0.removedReason == nil }.map(\.identifier))
        let rows = Set(settled.entries.map(\.identifier))
        let orphans = pending.filter { PushIdentifier.isOurs($0) && !held.contains($0) && !adding.contains($0) }
        let ours = settled.clearDelivered.filter(PushIdentifier.isOurs)
        if !ours.isEmpty { await deps.notifications.removeDelivered(ours) }
        guard !orphans.isEmpty else { return }
        await deps.notifications.removePending(orphans.sorted())
        for identifier in orphans where !rows.contains(identifier) {
            try? deps.records.remove(String(identifier.dropFirst(PushIdentifier.prefix.count)))
        }
    }

    /// Takes back scheduled pushes the preferences no longer allow (a day
    /// blocked, a bucket cooling down since they were scheduled), and with
    /// the fake AI off the fake AI's (a run that went on after the switch
    /// was turned off may have left some).
    func dropDisallowed() async {
        let preferences = deps.preferences.load()
        await removeActive(.menuDay) { preferences.isBlocked($0.belongsTo, photoIds: $0.photoIds) }
        await removeActive(.menuBucket) { preferences.multiplier(for: $0.bucket, at: $0.scheduledFor) == nil }
        if !deps.fakeAI() { _ = await takeBackFakeCopy() }
    }

    /// Takes back every active (non-debug) push `matching`: pending
    /// request removed, ledger row marked. A push whose time has passed
    /// already fired (or iOS dropped it): it is left for the reconcile to
    /// settle, so a delivered day never reads as taken back.
    func removeActive(_ reason: RemovalReason, matching: (LedgerEntry) -> Bool) async {
        let now = deps.now()
        var entries = deps.ledger.load()
        var identifiers: [String] = []
        for index in entries.indices
        where entries[index].isActive && entries[index].scheduledFor > now && matching(entries[index]) {
            entries[index].removedReason = reason
            entries[index].removedAt = now
            identifiers.append(entries[index].identifier)
        }
        guard !identifiers.isEmpty else { return }
        try? deps.ledger.save(entries)
        await deps.notifications.removePending(identifiers.filter(PushIdentifier.isOurs))
    }
}
