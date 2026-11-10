import MiraNoteKit
import SwiftUI
import UIKit

/// What the debug screen shows and does: the scheduler's snapshot,
/// refreshed on appear and after each action, and the page's buttons.
@MainActor
@Observable
final class TriggerDebugModel {
    private(set) var snapshot: SchedulerSnapshot?
    /// A replan is running.
    private(set) var isReplanning = false
    /// The ledger text was just copied.
    private(set) var copied = false

    private let scheduler: PushScheduler

    init(scheduler: PushScheduler) {
        self.scheduler = scheduler
    }

    func refresh() async {
        snapshot = await scheduler.snapshot()
    }

    func replan() async {
        guard !isReplanning else { return }
        isReplanning = true
        await refresh()
        await scheduler.replan()
        isReplanning = false
        await refresh()
    }

    func clearAll() async {
        await scheduler.clearAll()
        copied = false
        await refresh()
    }

    func unblock(day: String) async {
        await scheduler.unblockDay(day)
        await refresh()
    }

    func clearFewer(_ bucket: PushBucket) async {
        await scheduler.clearFewer(bucket)
        await refresh()
    }

    /// Text only: no photo ids, no coordinates, no key.
    func copyLedger() async {
        let entries = await scheduler.ledgerEntries()
        let current = await scheduler.snapshot()
        UIPasteboard.general.string = LedgerText.copy(entries: entries, runs: current.runs, counters: current.counters)
        copied = true
    }
}
