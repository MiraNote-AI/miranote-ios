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
    /// What the page "Themes" shows; nil until read, or in a build that
    /// finds no themes.
    private(set) var themes: ThemeSnapshot?

    private let scheduler: PushScheduler
    private let themeEngine: ThemeEngine?

    init(scheduler: PushScheduler, themeEngine: ThemeEngine? = nil) {
        self.scheduler = scheduler
        self.themeEngine = themeEngine
    }

    /// False in a build that finds no repeat themes.
    var findsThemes: Bool { themeEngine != nil }

    /// Reads every theme record: on the page's appearance and actions only.
    func refreshThemes() async {
        guard let themeEngine else { return }
        let read = await themeEngine.snapshot()
        if read != themes { themes = read }
    }

    /// Waits for a theme run in flight, as the engine does.
    func block(theme id: String) async {
        await themeEngine?.block(id)
        await refreshThemes()
    }

    func unblock(theme id: String) async {
        await themeEngine?.unblock(id)
        await refreshThemes()
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
