import Foundation

/// Which judge calls belong to a theme, for the debug page "Themes" (spec
/// 6.10, F1): its answers and re-asks, and beside a small theme's name the
/// phone's "where" lines of the groups Qwen made it from. Calls are linked
/// by theme id; a name is used only for what an id cannot say (a small
/// theme's group in its big theme's answer, an answer logged before new
/// piles' answers carried an id), and only while no other theme has it.
extension ThemeSnapshot {
    /// The theme's calls, newest first: those logged with its id (a new
    /// pile's answer that made it, a re-ask, a round 2); for a small theme
    /// also its big theme's round-1 answers with a group of its name, and
    /// their shorten calls; for a big theme an old answer with no id that
    /// gave its pile name. A theme renamed by the shorten round is not
    /// found by name.
    public func entries(of row: ThemeRow) -> [RoundLogEntry] {
        let named = Set(rounds.filter { namingGroup($0, of: row) != nil || namesPile($0, of: row) }.map(\.key))
        return rounds.filter { entry in
            entry.themeId == row.id || named.contains(entry.key)
                || entry.kind == "shorten" && entry.key.hasSuffix(Self.shortenSuffix)
                    && named.contains(String(entry.key.dropLast(Self.shortenSuffix.count)))
        }.reversed()
    }

    /// A small theme's "where" lines from the newest round-1 answer that
    /// named it: one per offered group it was made from, as the phone sent
    /// them. Empty for a big theme, when no logged answer named it, or when
    /// another small theme of its big theme has the same name.
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

    /// No other big theme has this name.
    private func isOnlyBig(named name: String) -> Bool {
        themes.filter { $0.kind == .big && $0.name == name }.count == 1
    }

    /// An old new-pile answer (logged with no theme id) that gave the big
    /// theme its name, while the name is the big theme's alone.
    private func namesPile(_ entry: RoundLogEntry, of row: ThemeRow) -> Bool {
        row.kind == .big && entry.themeId == nil && isOnlyBig(named: row.name) && answer(entry)?.pileName == row.name
    }

    /// The group of a small theme's name in an answer about its big theme
    /// (by id; by the pile name for an old answer with no id), while no
    /// other small theme of that big theme has the name.
    private func namingGroup(_ entry: RoundLogEntry, of row: ThemeRow) -> RoundOneAnswer.Group? {
        guard row.kind == .small, let parentId = row.parentId, let answer = answer(entry) else { return nil }
        let twins = themes.filter { $0.kind == .small && $0.parentId == parentId && $0.name == row.name }
        guard twins.count == 1 else { return nil }
        let aboutParent: Bool
        if let themeId = entry.themeId {
            aboutParent = themeId == parentId
        } else if let parent = themes.first(where: { $0.id == parentId }) {
            aboutParent = isOnlyBig(named: parent.name) && answer.pileName == parent.name
        } else {
            aboutParent = false
        }
        return aboutParent ? answer.groups.first { $0.name == row.name } : nil
    }
}
