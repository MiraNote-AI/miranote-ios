import MiraNoteKit
import SwiftUI

/// "Grouping results": the last run's groups per day -- thumbnails (on the
/// phone only), counts, the six scores, bucket, eligibility, scheduled day
/// and AI status -- and the photos set aside as utility (acceptance F4).
struct TriggerGroupingScreen: View {
    let controller: TriggerController
    let model: TriggerDebugModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let snapshot = model.snapshot {
                    threshold(snapshot.threshold)
                    if snapshot.groups.isEmpty {
                        Text("No grouping yet. Open the app again or press Replan.")
                            .font(.miraCaption).foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(days(snapshot.groups), id: \.day) { day, groups in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: TriggerWords.shortDate(day)).font(.miraLabel).foregroundStyle(Palette.ink)
                            ForEach(groups, id: \.report.groupKey) { group in
                                card(group)
                            }
                        }
                    }
                    utility(snapshot.utilityPhotoIds)
                }
            }
            .padding(Metrics.chromeInset)
        }
        .background(Palette.paper)
        .navigationTitle("Grouping results")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("debug.grouping")
        .refreshable { await model.refresh() }
        .task { await model.refresh() }
    }

    private func days(_ groups: [SchedulerSnapshot.Group]) -> [(day: String, groups: [SchedulerSnapshot.Group])] {
        Dictionary(grouping: groups, by: \.report.belongsTo)
            .map { (day: $0.key, groups: $0.value) }
            .sorted { $0.day > $1.day }
    }

    @ViewBuilder private func threshold(_ result: ThresholdResult?) -> some View {
        if let result {
            let minutes = String(format: "%.0f", result.value / 60)
            Text("A long gap between photos starts a new group after \(minutes) min")
                .font(.miraCaption).foregroundStyle(Palette.textSecondary)
        }
    }

    private func card(_ group: SchedulerSnapshot.Group) -> some View {
        let report = group.report
        return VStack(alignment: .leading, spacing: 6) {
            TriggerThumbStrip(photos: controller.photos, ids: report.photoIds)
            Text(verbatim: [TriggerDebugText.bucket(report.bucket),
                            String(appCopy: "Photos \(report.uniqueCount) (\(report.rawCount) with repeats)")]
                .joined(separator: TriggerWords.separator))
                .font(.miraLabel).foregroundStyle(Palette.ink)
            if let score = report.score {
                let lines = TriggerDebugText.breakdown(score)
                Text(verbatim: lines[0]).font(.miraCaption).foregroundStyle(Palette.textSecondary)
                Text(verbatim: lines[1]).font(.miraCaption).foregroundStyle(Palette.textSecondary)
                Text(verbatim: lines[2]).font(.miraCaption).foregroundStyle(Palette.ink)
            } else {
                Text("No score").font(.miraCaption).foregroundStyle(Palette.textSecondary)
            }
            if let reason = report.ineligible {
                TriggerDebugText.reason(reason).font(.miraCaption).foregroundStyle(Palette.ink)
            } else {
                Text("Can go out").font(.miraCaption).foregroundStyle(Palette.ink)
            }
            if let day = group.scheduledDay {
                Text("Scheduled for \(TriggerWords.shortDate(day))")
                    .font(.miraCaption).foregroundStyle(Palette.textSecondary)
            }
            TriggerDebugText.ai(group.aiStatus).font(.miraCaption).foregroundStyle(Palette.textSecondary)
        }
        .debugCard()
        .accessibilityIdentifier("debug.group")
    }

    @ViewBuilder private func utility(_ ids: [String]) -> some View {
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set aside as documents and the like (\(ids.count))")
                    .font(.miraLabel).foregroundStyle(Palette.ink)
                TriggerThumbStrip(photos: controller.photos, ids: ids, limit: 12)
            }
            .debugCard()
            .accessibilityIdentifier("debug.utility")
        }
    }
}

/// "Category report": how the recent photos fall into the seven buckets, a
/// few examples each, and the raw labels most often seen in Other. On
/// screen only (nothing is exported).
struct TriggerCategoryScreen: View {
    let controller: TriggerController
    let model: TriggerDebugModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let report = model.snapshot?.categories ?? .empty
                if report.buckets.isEmpty {
                    Text("No report yet. Open the app again or press Replan.")
                        .font(.miraCaption).foregroundStyle(Palette.textSecondary)
                }
                ForEach(report.buckets, id: \.bucket) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(verbatim: TriggerDebugText.bucket(entry.bucket)).font(.miraLabel)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text(verbatim: "\(entry.count)").font(.miraLabel).foregroundStyle(Palette.ink)
                        }
                        if !entry.examples.isEmpty {
                            TriggerThumbStrip(photos: controller.photos, ids: entry.examples, limit: 6)
                        }
                        if entry.bucket == .other, !report.otherLabels.isEmpty {
                            Text(verbatim: report.otherLabels.map { "\($0.label) \($0.count)" }.joined(separator: ", "))
                                .font(.miraCaption).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .debugCard()
                    .accessibilityIdentifier("debug.category.\(entry.bucket.rawValue)")
                }
            }
            .padding(Metrics.chromeInset)
        }
        .background(Palette.paper)
        .navigationTitle("Category report")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("debug.categories")
        .refreshable { await model.refresh() }
        .task { await model.refresh() }
    }
}
