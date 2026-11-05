import Foundation

/// The ledger and run log as plain text a tester can paste into chat. No
/// photo ids, no coordinates, no keys: only days, buckets and place names.
public enum LedgerText {
    public static func copy(entries: [LedgerEntry], runs: [ScheduleRun], counters: ScheduleCounters) -> String {
        var lines = ["Pushes (\(entries.count))"]
        lines += entries.sorted { $0.scheduledFor < $1.scheduledFor }.map(pushLine)
        lines.append("Runs (\(runs.count)), left before result: \(counters.leftBeforeResult)")
        lines += runs.map(runLine)
        return lines.joined(separator: "\n")
    }

    private static func pushLine(_ entry: LedgerEntry) -> String {
        var actions: [String] = []
        if entry.deliveredAt != nil { actions.append("delivered") }
        if let reason = entry.notDeliveredReason { actions.append("not delivered: \(reason)") }
        if entry.openedAt != nil { actions.append("opened") }
        if entry.madePageAt != nil { actions.append("made page") }
        if entry.notOpened { actions.append("not opened") }
        if let menu = entry.menuAction { actions.append("menu: \(menu.rawValue)") }
        if let removed = entry.removedReason { actions.append("removed: \(removed.rawValue)") }
        if entry.isDebug { actions.append("debug") }
        let score = String(format: "%.2f", entry.score.total)
        return [entry.belongsTo, stamp(entry.scheduledFor), entry.bucket.rawValue, entry.place ?? "-", score,
                "question \(entry.questionType ?? "-")",
                actions.isEmpty ? "scheduled" : actions.joined(separator: ", ")].joined(separator: " | ")
    }

    private static func runLine(_ run: ScheduleRun) -> String {
        let days = run.scheduledDays.isEmpty ? "none" : run.scheduledDays.joined(separator: ",")
        var line = "\(stamp(run.startedAt)) | \(run.trigger) | fragments \(run.fragments), candidates "
            + "\(run.candidates), ai \(run.aiSent) | scheduled: \(days)"
        let empty = run.emptyDays.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
        if !empty.isEmpty { line += " | empty: " + empty.joined(separator: ", ") }
        let errors = (run.groups.filter { $0.outcome == .error }.map { $0.message ?? "error" }
            + (run.error.map { [$0] } ?? [])).map(safe)
        if !errors.isEmpty { line += " | errors: " + errors.joined(separator: "; ") }
        let clashes = run.questionClashes.map { "\($0.slotDay) \($0.types.joined(separator: "/"))" }
        if !clashes.isEmpty { line += " | question types taken nearby: " + clashes.joined(separator: ", ") }
        return line
    }

    /// A backend's words can echo a credential: such a line is not copied.
    private static func safe(_ message: String) -> String {
        let lower = message.lowercased()
        let secret = ["bearer", "token", "api_key", "apikey", "api-key", "sk-", "authorization"]
        return secret.contains { lower.contains($0) } ? "error (text withheld)" : message
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
