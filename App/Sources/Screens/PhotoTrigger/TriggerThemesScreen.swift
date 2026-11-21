import MiraNoteKit
import SwiftUI

/// "Themes" (spec 6.10, acceptance F1-F3): what the repeat-theme finder
/// found -- its last runs, tonight's piles, every theme with the pile it
/// follows, the blocked themes -- and a test push of any theme. Ids, names
/// and counts only: no photo, no file name.
struct TriggerThemesScreen: View {
    let controller: TriggerController
    let model: TriggerDebugModel
    /// The theme whose "Test-push this theme" was pressed last here.
    @State private var pressed: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !model.findsThemes {
                    note("Repeat themes are not set up in this build")
                } else if let snapshot = model.themes {
                    TriggerThemeRunsSection(runs: snapshot.runs)
                    TriggerThemePilesSection(snapshot: snapshot)
                    themesSection(snapshot)
                    blockedSection(snapshot)
                } else {
                    note("Loading...")
                }
            }
            .padding(Metrics.chromeInset)
        }
        .background(Palette.paper)
        .navigationTitle("Themes")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("themes.screen")
        .refreshable { await model.refreshThemes() }
        .task { await model.refreshThemes() }
        .onChange(of: controller.isRunning) { _, _ in Task { await model.refreshThemes() } }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.miraCaption).foregroundStyle(Palette.textSecondary)
    }

    private func themesSection(_ snapshot: ThemeSnapshot) -> some View {
        TriggerDebugSection(id: "themes.list", title: "Themes") {
            let rows = Self.ordered(snapshot.themes)
            if rows.isEmpty { note("No theme yet") }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    TriggerThemeFacts(row: row, snapshot: snapshot)
                    HStack(spacing: 8) {
                        Button("Test-push this theme") {
                            pressed = row.id
                            controller.tryTheme(row.id)
                        }
                        .buttonStyle(SoftPill())
                        .disabled(controller.isRunning)
                        .accessibilityIdentifier("themes.tryTheme")
                        NavigationLink {
                            TriggerThemeDetailScreen(model: model, themeId: row.id)
                        } label: {
                            Text("Round answers (\(snapshot.entries(of: row).count))")
                        }
                        .buttonStyle(SoftPill())
                        .accessibilityIdentifier("themes.details")
                    }
                    if pressed == row.id, !controller.steps.isEmpty {
                        TriggerProgressList(controller: controller)
                    }
                }
                .padding(.leading, row.kind == .small ? 16 : 0)
                .padding(.vertical, 4)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("themes.theme")
            }
        }
    }

    /// Themes with status blocked, each with its clear button (F3).
    private func blockedSection(_ snapshot: ThemeSnapshot) -> some View {
        TriggerDebugSection(id: "themes.blocked", title: "Blocked themes") {
            let blocked = snapshot.themes.filter { $0.status == .blocked }
            if blocked.isEmpty { note("No theme is blocked") }
            ForEach(blocked) { row in
                HStack {
                    Text(verbatim: TriggerThemeFacts.name(row)).font(.miraCaption).foregroundStyle(Palette.ink)
                        .accessibilityIdentifier("themes.blocked")
                    Spacer()
                    Button("Clear") { Task { await model.unblock(theme: row.id) } }
                        .buttonStyle(SoftPill())
                        .accessibilityIdentifier("themes.clear")
                }
            }
        }
    }

    /// Each big theme, then its small themes; small themes whose big theme
    /// is gone last.
    static func ordered(_ rows: [ThemeRow]) -> [ThemeRow] {
        let bigs = rows.filter { $0.kind == .big }
        let bigIds = Set(bigs.map(\.id))
        let smalls = rows.filter { $0.kind == .small }
        return bigs.flatMap { big in [big] + smalls.filter { $0.parentId == big.id } }
            + smalls.filter { !bigIds.contains($0.parentId ?? "") }
    }
}

/// One theme's facts: name, noun, status, the pile it follows and its share
/// (yellow at 20-50%), photos, days, cooldown, and for a small theme
/// Qwen's group name beside the phone's "where" line.
struct TriggerThemeFacts: View {
    let row: ThemeRow
    let snapshot: ThemeSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: Self.name(row)).font(.miraLabel).foregroundStyle(Palette.ink)
                Spacer()
                Text(row.kind == .big ? "Big theme" : "Small theme")
                    .font(.miraCaption).foregroundStyle(Palette.textSecondary)
            }
            caption(Text("Noun: \(row.noun.isEmpty ? "-" : row.noun)"))
            caption(Text("Status: \(row.status.rawValue)"))
            if row.kind == .big { follow }
            caption(Text("Photos \(row.members.count), days \(snapshot.days[row.id] ?? 0)"))
            // Phase 1 pushes no theme on its own: no cooldown yet.
            caption(Text("Cooldown: -"))
            if row.kind == .small { groupWhere }
        }
    }

    static func name(_ row: ThemeRow) -> String {
        row.name.isEmpty ? "-" : row.name
    }

    private func caption(_ text: Text) -> some View {
        text.font(.miraCaption).foregroundStyle(Palette.textSecondary)
    }

    /// The pile followed tonight and the share of the theme's old photos in
    /// it, marked when the claim flagged it (20% up to 50%: followed, but
    /// much of the theme is elsewhere) -- the Kit's rule, read off the row.
    @ViewBuilder private var follow: some View {
        let ratio = row.followRatio
        let flagged = row.flagged && ratio != nil
        Group {
            if let ratio, let pile = snapshot.follows[row.id] {
                Text("Follows pile \(pile + 1), \(Self.percent(ratio))")
            } else if let ratio {
                Text("Follows no pile, \(Self.percent(ratio))")
            } else {
                Text("Not claimed yet")
            }
        }
        .font(.miraCaption)
        .foregroundStyle(flagged ? Palette.ink : Palette.textSecondary)
        .padding(.horizontal, flagged ? 4 : 0)
        .background(flagged ? Color.debugFlag : .clear, in: RoundedRectangle(cornerRadius: 3))
        .accessibilityIdentifier("themes.follow")
        .accessibilityValue(flagged ? Text("flagged") : Text(verbatim: ""))
    }

    /// Qwen's name for the group beside the phone's "where" line of the
    /// groups it was made from (E2 saw them disagree).
    private var groupWhere: some View {
        let lines = snapshot.whereLines(of: row)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Qwen: \(Self.name(row))").foregroundStyle(Palette.ink)
            Text("Phone: \(lines.isEmpty ? "-" : lines.joined(separator: " / "))")
                .foregroundStyle(Palette.ink)
        }
        .font(.miraCaption)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("themes.groupWhere")
    }

    /// Rounded down to a tenth, so a share under 50% never reads "50%"
    /// ("49.9%"); a whole number shows no decimal ("100%").
    static func percent(_ value: Double) -> String {
        // The nudge keeps 0.29 (289.99999...) from flooring to 28.9.
        let tenths = Int((value * 1000 + 1e-9).rounded(.down))
        return tenths % 10 == 0 ? "\(tenths / 10)%" : "\(tenths / 10).\(tenths % 10)%"
    }
}

/// "Last runs": newest first, with their measured time and memory.
struct TriggerThemeRunsSection: View {
    let runs: [ThemeRunReport]

    var body: some View {
        TriggerDebugSection(id: "themes.runs", title: "Last runs") {
            if runs.isEmpty {
                Text("No theme run yet").font(.miraCaption).foregroundStyle(Palette.textSecondary)
            }
            ForEach(Array(runs.reversed().enumerated()), id: \.offset) { _, run in
                block(run)
            }
        }
    }

    private func block(_ run: ThemeRunReport) -> some View {
        let memory = run.peakMemoryMB.map { String(format: "%.0f MB", $0) } ?? "-"
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(TriggerDebugText.stamp(run.at))  \(run.trigger.rawValue)")
                .font(.miraLabel).foregroundStyle(run.failures.isEmpty ? Palette.ink : Color.debugError)
            Group {
                Text("Photos \(run.photos), checked \(run.checkedNew)")
                Text("Moments \(run.moments), piles \(run.piles.count)")
                Text("Checkup \(run.checkupMs) ms, cluster \(run.clusterMs) ms")
                Text("Memory \(memory), asked \(run.asked)")
            }
            .font(.miraCaption).foregroundStyle(Palette.textSecondary)
            ForEach(Array(run.failures.enumerated()), id: \.offset) { _, failure in
                Text(verbatim: failure).font(.miraCaption).foregroundStyle(Color.debugError)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("themes.run")
    }
}

/// "Tonight's piles": the last run that clustered in this launch, with the
/// themes that follow each.
struct TriggerThemePilesSection: View {
    let snapshot: ThemeSnapshot

    var body: some View {
        TriggerDebugSection(id: "themes.piles", title: "Tonight's piles") {
            if snapshot.piles.isEmpty {
                Text("No piles in this launch yet").font(.miraCaption).foregroundStyle(Palette.textSecondary)
            }
            ForEach(Array(snapshot.piles.enumerated()), id: \.offset) { index, pile in
                let share = TriggerThemeFacts.percent(pile.maxDayShare)
                let names = snapshot.themes.filter { snapshot.follows[$0.id] == index }.map(TriggerThemeFacts.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pile \(index + 1): \(pile.days) days, \(pile.momentIds.count) moments, top day \(share)")
                        .foregroundStyle(Palette.ink)
                    if !names.isEmpty {
                        Text("Followed by \(names.joined(separator: ", "))").foregroundStyle(Palette.textSecondary)
                    }
                }
                .font(.miraCaption)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("themes.pile")
            }
        }
    }
}

extension Color {
    /// A ratio to look at on the Themes page.
    static let debugFlag = Color(hex: 0xF6DD7A)
}
