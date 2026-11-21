import Foundation

/// Which judge calls belong to a theme, for the debug page "Themes" (spec
/// 6.10, F1): its answers and re-asks, and beside a small theme's name the
/// phone's "where" lines of the groups Qwen made it from.
extension ThemeSnapshot {
    /// The theme's calls, newest first: those made for it (a re-ask, a round
    /// 2), and the round-1 answers that named it -- for a big theme a new
    /// pile's answer with its pile name, for a small theme its big theme's
    /// answers with a group of its name -- with their shorten calls. A theme
    /// renamed by the shorten round is not found in its first answer.
    public func entries(of row: ThemeRow) -> [RoundLogEntry] {
        let named = Set(rounds.filter { namingGroup($0, of: row) != nil || namesPile($0, of: row) }.map(\.key))
        return rounds.filter { entry in
            entry.themeId == row.id || named.contains(entry.key)
                || entry.kind == "shorten" && named.contains(String(entry.key.dropLast(Self.shortenSuffix.count)))
                    && entry.key.hasSuffix(Self.shortenSuffix)
        }.reversed()
    }

    /// A small theme's "where" lines from the newest round-1 answer that
    /// named it: one per offered group it was made from, as the phone sent
    /// them. Empty for a big theme, or when no logged answer named it.
    public func whereLines(of row: ThemeRow) -> [String] {
        for entry in rounds.reversed() {
            guard let group = namingGroup(entry, of: row) else { continue }
            return group.from.compactMap { entry.where[$0] }
        }
        return []
    }

    /// Theme id -> the different local days its members with a record were taken on.
    static func days(of rows: [ThemeRow], photos: [String: ThemePhoto], calendar: Calendar) -> [String: Int] {
        Dictionary(rows.map { row in
            let taken = row.members.compactMap { photos[$0]?.takenAt }
            return (row.id, Set(taken.map { PushPhotoPicker.day($0, calendar: calendar) }).count)
        }, uniquingKeysWith: { first, _ in first })
    }

    private static let shortenSuffix = "-shorten"

    private func answer(_ entry: RoundLogEntry) -> RoundOneAnswer? {
        guard entry.kind == "round1", case .success(let answer) = RoundOneAnswer.parse(entry.reply) else {
            return nil
        }
        return answer
    }

    /// A new pile's answer (no theme id yet) that gave the big theme its name.
    private func namesPile(_ entry: RoundLogEntry, of row: ThemeRow) -> Bool {
        row.kind == .big && entry.themeId == nil && answer(entry)?.pileName == row.name
    }

    /// The group of a small theme's name in an answer about its big theme.
    private func namingGroup(_ entry: RoundLogEntry, of row: ThemeRow) -> RoundOneAnswer.Group? {
        guard row.kind == .small, let parentId = row.parentId, let answer = answer(entry) else { return nil }
        let parent = themes.first { $0.id == parentId }
        let aboutParent = entry.themeId == parentId || entry.themeId == nil && answer.pileName == parent?.name
        return aboutParent ? answer.groups.first { $0.name == row.name } : nil
    }
}
