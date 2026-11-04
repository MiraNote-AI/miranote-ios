import MiraNoteKit
import SwiftUI

/// "Scheduled pushes": the next seven nights, each with its push or why it
/// is empty (acceptance F2).
struct TriggerScheduledSection: View {
    let snapshot: SchedulerSnapshot?

    var body: some View {
        TriggerDebugSection(id: "scheduled", title: "Scheduled pushes") {
            if let snapshot {
                ForEach(snapshot.days, id: \.slotDay) { day in
                    row(day)
                }
            } else {
                Text("Loading...").font(.miraCaption).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    @ViewBuilder private func row(_ day: SchedulerSnapshot.Day) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: TriggerDebugText.slot(day)).font(.miraLabel).foregroundStyle(Palette.ink)
            if let entry = day.entry {
                let place = entry.place ?? String(appCopy: "No place")
                Text(verbatim: [TriggerDebugText.bucket(entry.bucket), place,
                                String(appCopy: "Score \(TriggerDebugText.score(entry.score.total))")]
                    .joined(separator: TriggerWords.separator))
                    .font(.miraCaption).foregroundStyle(Palette.textSecondary)
                Text("From \(TriggerWords.shortDate(entry.belongsTo))")
                    .font(.miraCaption).foregroundStyle(Palette.textSecondary)
            } else {
                TriggerDebugText.emptyReason(day.emptyReason)
                    .font(.miraCaption).foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(day.entry == nil ? "debug.empty.\(day.slotDay)" : "debug.push.\(day.slotDay)")
    }
}

/// "Schedule log": the last runs, errors in red (acceptance F3).
struct TriggerLogSection: View {
    let snapshot: SchedulerSnapshot?

    var body: some View {
        TriggerDebugSection(id: "log", title: "Schedule log", open: false) {
            if let snapshot {
                Text("Left before the answer: \(snapshot.counters.leftBeforeResult)")
                    .font(.miraCaption).foregroundStyle(Palette.textSecondary)
                if snapshot.runs.isEmpty {
                    Text("No runs yet").font(.miraCaption).foregroundStyle(Palette.textSecondary)
                }
                ForEach(Array(snapshot.runs.enumerated()), id: \.offset) { _, run in
                    runBlock(run)
                }
            }
        }
    }

    private func runBlock(_ run: ScheduleRun) -> some View {
        let tint = run.hasError ? Color.debugError : Palette.textSecondary
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(TriggerDebugText.stamp(run.startedAt))  \(run.trigger)")
                .font(.miraLabel).foregroundStyle(run.hasError ? Color.debugError : Palette.ink)
            Text("Groups \(run.fragments), candidates \(run.candidates), sent to the AI \(run.aiSent)")
                .font(.miraCaption).foregroundStyle(Palette.textSecondary)
            if !run.scheduledDays.isEmpty {
                let days = run.scheduledDays.map(TriggerWords.shortDate).joined(separator: ", ")
                Text(verbatim: String(appCopy: "Scheduled: \(days)"))
                    .font(.miraCaption).foregroundStyle(Palette.textSecondary)
            }
            ForEach(Array(run.groups.enumerated()), id: \.offset) { _, group in
                HStack(spacing: 4) {
                    Text(verbatim: "\(TriggerWords.shortDate(group.belongsTo)) ->")
                    TriggerDebugText.outcome(group.outcome)
                    if let message = group.message { Text(verbatim: message) }
                    Text(verbatim: String(appCopy: "\(Int(group.seconds.rounded())) s"))
                        .accessibilityIdentifier("debug.run.groupTime")
                }
                .font(.miraCaption)
                .foregroundStyle(group.outcome == .error ? Color.debugError : Palette.textSecondary)
            }
            ForEach(run.emptyDays.sorted { $0.key < $1.key }, id: \.key) { day, code in
                HStack(spacing: 4) {
                    Text(verbatim: "\(TriggerWords.shortDate(day)):")
                    TriggerDebugText.emptyReason(code)
                }
                .font(.miraCaption).foregroundStyle(Palette.textSecondary)
            }
            if let error = run.error {
                Text(verbatim: error).font(.miraCaption).foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("debug.run")
    }
}

/// "Blocked days / fewer buckets", each with a clear button (acceptance F5).
struct TriggerBlockedSection: View {
    let model: TriggerDebugModel

    var body: some View {
        TriggerDebugSection(id: "blocked", title: "Blocked days and fewer buckets") {
            if let preferences = model.snapshot?.preferences {
                let days = preferences.blockedDays.sorted { $0.key < $1.key }
                let fewer = preferences.fewer.sorted { $0.value < $1.value }
                if days.isEmpty && fewer.isEmpty {
                    Text("Nothing is blocked").font(.miraCaption).foregroundStyle(Palette.textSecondary)
                }
                ForEach(days, id: \.key) { day, since in
                    let when = TriggerDebugText.stamp(since)
                    clearRow(Text("Day \(TriggerWords.shortDate(day)) is blocked, since \(when)"),
                             id: "debug.unblock.\(day)") { await model.unblock(day: day) }
                }
                ForEach(fewer, id: \.key) { bucket, since in
                    let when = TriggerDebugText.stamp(since)
                    clearRow(Text(verbatim: String(appCopy: "Fewer \(TriggerDebugText.bucket(bucket)), since \(when)")),
                             id: "debug.clearFewer.\(bucket.rawValue)") { await model.clearFewer(bucket) }
                }
            }
        }
    }

    private func clearRow(_ label: Text, id: String, action: @escaping () async -> Void) -> some View {
        HStack {
            label.font(.miraCaption).foregroundStyle(Palette.ink)
            Spacer()
            Button("Clear") { Task { await action() } }
                .buttonStyle(SoftPill())
                .accessibilityIdentifier(id)
        }
    }
}
