import MiraNoteKit
import SwiftUI

/// One theme on the Themes page: its facts, block or clear, and every judge
/// call about it -- the raw answers and the re-asks (the same key is the
/// same question), newest first (spec 6.10, F1, F3).
struct TriggerThemeDetailScreen: View {
    let model: TriggerDebugModel
    let themeId: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let snapshot = model.themes, let row = snapshot.themes.first(where: { $0.id == themeId }) {
                    VStack(alignment: .leading, spacing: 6) {
                        TriggerThemeFacts(row: row, snapshot: snapshot)
                        Text("Same every time: \(row.samePart.isEmpty ? "-" : row.samePart)")
                            .font(.miraCaption).foregroundStyle(Palette.textSecondary)
                        blockButton(row)
                    }
                    .debugCard()
                    rounds(snapshot.entries(of: row))
                } else {
                    Text("The theme is no longer in the library")
                        .font(.miraCaption).foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(Metrics.chromeInset)
        }
        .background(Palette.paper)
        .navigationTitle("Round answers")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshThemes() }
    }

    @ViewBuilder private func blockButton(_ row: ThemeRow) -> some View {
        if row.status == .blocked {
            Button("Clear the block") { Task { await model.unblock(theme: row.id) } }
                .buttonStyle(SoftPill())
                .accessibilityIdentifier("themes.unblock")
        } else {
            Button("Block this theme") { Task { await model.block(theme: row.id) } }
                .buttonStyle(SoftPill())
                .disabled(row.status == .sensitive)
                .accessibilityIdentifier("themes.block")
        }
    }

    @ViewBuilder private func rounds(_ entries: [RoundLogEntry]) -> some View {
        if entries.isEmpty {
            Text("No round answer is logged for this theme")
                .font(.miraCaption).foregroundStyle(Palette.textSecondary)
        }
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "\(TriggerDebugText.stamp(entry.at))  \(entry.kind)")
                    .font(.miraLabel).foregroundStyle(entry.problem == nil ? Palette.ink : Color.debugError)
                    .accessibilityIdentifier("themes.round")
                Text(verbatim: entry.key).font(.miraCaption).foregroundStyle(Palette.textSecondary)
                usage(entry.usage)
                if let problem = entry.problem {
                    Text("Not used: \(problem.rawValue)").font(.miraCaption).foregroundStyle(Color.debugError)
                }
                ForEach(entry.where.sorted { $0.key < $1.key }, id: \.key) { group, line in
                    Text(verbatim: "\(group): \(line)").font(.miraCaption).foregroundStyle(Palette.ink)
                }
                Text(verbatim: entry.reply)
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .debugCard()
        }
    }

    private func usage(_ usage: RoundUsage) -> some View {
        let cost = String(format: "%.5f", usage.costCny)
        return Text("Tokens \(usage.promptTokens) + \(usage.completionTokens), \(cost) CNY, \(usage.model)")
            .font(.miraCaption).foregroundStyle(Palette.textSecondary)
    }
}
