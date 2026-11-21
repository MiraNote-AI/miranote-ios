import Foundation

/// The theme library: big themes with their small themes, kept in one file
/// (`themes/library.json`). Pure rules (`apply`, `removing`) plus the file.
public struct ThemeLibrary: Sendable {
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    public static var defaultFile: URL {
        PhotoTriggerPaths.root.appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    /// The stored rows; a file that cannot be read is set aside and loads empty.
    /// A row this build cannot decode costs that row only.
    public func load() -> [ThemeRow] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        if let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder().decode(LenientFile.self, from: data) {
            return stored.themes.compactMap(\.value)
        }
        PhotoTriggerPaths.setAside(file)
        return []
    }

    public func save(_ rows: [ThemeRow]) throws {
        try PhotoTriggerPaths.prepare(file.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(File(themes: rows)).write(to: file, options: .atomic)
    }

    private struct File: Encodable {
        let version = 1
        let themes: [ThemeRow]
    }

    private struct LenientFile: Decodable {
        let themes: [Lenient<ThemeRow>]
    }

    // MARK: - Round 1 answer

    // swiftlint:disable function_parameter_count
    /// Creates or updates the big row of `pile` and its small rows from a
    /// round-1 answer (spec 6.5, D5, D7). Returns the whole library: `existing`
    /// with this pile's rows replaced.
    ///
    /// - A sensitive answer marks the big row `sensitive` and retires its small rows (they stay).
    /// - Same-name small rows keep their id and take the new rule; new names get
    ///   new ids; missing ones become `retired`.
    /// - A changed split retires every old small row (new ones get new ids),
    ///   except a name that was already retired, which comes back with its old id.
    /// - Images the judge put in `notInPile` leave the big row's members.
    /// - A new big row takes `newId` (the id its answer was logged with), or a new UUID.
    static func apply(_ answer: RoundOneAnswer, to big: ThemeRow?, pile: Pile, moments: [String: Moment],
                      groups: (a: [SplitGroup], b: [SplitGroup]), sample: [SampledPhoto],
                      existing: [ThemeRow], newId: String? = nil) -> [ThemeRow] {
        let bigId = big?.id ?? newId ?? UUID().uuidString
        let outside = Set(answer.notInPile.compactMap { number in
            sample.indices.contains(number - 1) ? sample[number - 1].momentId : nil
        })
        let members = pile.momentIds.filter { !outside.contains($0) }.flatMap { moments[$0]?.photoIds ?? [] }
        let inherited = big?.status == .blocked || big?.status == .frozen ? big?.status : nil
        let row = ThemeRow(id: bigId, kind: .big, parentId: nil, name: answer.pileName ?? big?.name ?? "",
                           noun: answer.pileNoun ?? big?.noun ?? "", samePart: "",
                           split: answer.chosen, status: answer.sensitive ? .sensitive : inherited ?? .active,
                           center: pile.center, rule: nil, members: members, lastAskedCount: members.count,
                           flagged: big?.flagged ?? false, followRatio: big?.followRatio, where: big?.where)
        let others = existing.filter { $0.id != bigId && $0.parentId != bigId }
        let old = existing.filter { $0.kind == .small && $0.parentId == bigId }
        if answer.sensitive { return others + [row] + retiredCopies(of: old) }

        let splitChanged = big?.split.map { $0 != answer.chosen } ?? false
        let fresh = smallRows(answer, parent: row, groups: groups, moments: moments, old: old,
                              splitChanged: splitChanged)
        let used = Set(fresh.map(\.id))
        let missing = retiredCopies(of: old.filter { !used.contains($0.id) })
        return others + [row] + fresh + missing
    }

    /// Every theme that ever appeared stays; it is only marked `retired`.
    private static func retiredCopies(of rows: [ThemeRow]) -> [ThemeRow] {
        rows.map { small in
            var retired = small
            if retired.status != .blocked { retired.status = .retired }
            return retired
        }
    }

    private static func smallRows(_ answer: RoundOneAnswer, parent: ThemeRow,
                                  groups: (a: [SplitGroup], b: [SplitGroup]), moments: [String: Moment],
                                  old: [ThemeRow], splitChanged: Bool) -> [ThemeRow] {
        guard answer.chosen == "A" || answer.chosen == "B" else { return [] }
        let offered = Dictionary((groups.a + groups.b).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inBig = Set(parent.members)
        // A changed split keeps ids only for names that were already retired.
        let reusable = old.filter { !splitChanged || $0.status == .retired }
        var taken = Set<String>()
        var rows: [ThemeRow] = []
        for group in answer.groups {
            let sources = group.from.compactMap { offered[$0] }
            guard let first = sources.first, !group.name.isEmpty else { continue }
            let rule = rule(for: answer.chosen, group: group, sources: sources)
            let photos = sources.flatMap(\.momentIds).flatMap { moments[$0]?.photoIds ?? [] }
            let found = reusable.first { $0.name == group.name && !taken.contains($0.id) }
            let status = found.map { $0.status == .retired ? ThemeStatus.active : $0.status } ?? .active
            let members = unique(photos).filter(inBig.contains)
            taken.insert(found?.id ?? "")
            rows.append(ThemeRow(id: found?.id ?? UUID().uuidString, kind: .small, parentId: parent.id,
                                 name: group.name, noun: group.noun ?? "", samePart: group.samePart ?? "",
                                 split: answer.chosen, status: status, center: nil, rule: rule,
                                 members: members, lastAskedCount: members.count,
                                 flagged: found?.flagged ?? false, followRatio: found?.followRatio,
                                 where: first.where))
        }
        return rows
    }

    // swiftlint:enable function_parameter_count

    private static func rule(for chosen: String, group: RoundOneAnswer.Group, sources: [SplitGroup]) -> SubRule {
        if chosen == "A" {
            return .content(evidence: group.evidence.isEmpty ? unique(sources.map(\.key)) : group.evidence)
        }
        var keys: [OccasionKey] = []
        for source in sources {
            let parts = source.key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { continue }
            let key = OccasionKey(place: source.placeCenter, daypart: parts[1], weekpart: parts[2])
            if !keys.contains(key) { keys.append(key) }
        }
        return .occasion(keys: keys)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    // MARK: - Deleted photos

    /// Drops `deleted` photo ids from every row. A row is removed only when
    /// it had members and all of them were deleted (D8); a small row that is
    /// empty because tonight's rule matched nothing stays. A small row whose
    /// big row is removed goes with it. A sensitive or blocked row is never
    /// touched (D5, F7): it is what keeps its pile from being sent again.
    static func removing(_ deleted: Set<String>, from rows: [ThemeRow]) -> [ThemeRow] {
        var removed = Set<String>()
        var kept: [ThemeRow] = []
        for var row in rows {
            if row.status == .sensitive || row.status == .blocked {
                kept.append(row)
                continue
            }
            let remaining = row.members.filter { !deleted.contains($0) }
            if !row.members.isEmpty, remaining.isEmpty {
                removed.insert(row.id)
                continue
            }
            row.members = remaining
            kept.append(row)
        }
        return kept.filter { $0.parentId.map { !removed.contains($0) } ?? true }
    }
}
