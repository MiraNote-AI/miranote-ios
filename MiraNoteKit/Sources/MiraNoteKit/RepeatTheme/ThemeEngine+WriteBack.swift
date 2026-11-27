import Foundation

extension ThemeEngine {
    // MARK: - Claim results on the rows

    /// Tonight's claim on the rows: a big row takes its ratio, flag and list;
    /// a small row its rule's list within its big row's (`SubThemeRule`).
    /// Active and frozen rows go frozen or active with the claim (a small
    /// one with its big one); blocked, sensitive and retired stay as they are.
    static func writeBack(_ claim: ClaimResult, to rows: [ThemeRow], moments: [String: Moment],
                          photos: [String: ThemePhoto], calendar: Calendar) -> [ThemeRow] {
        // A photo round 1 left out stays out of the big list and the small ones.
        var claim = claim
        for row in rows where row.kind == .big {
            guard let excluded = row.excluded, !excluded.isEmpty, let tonight = claim.members[row.id] else { continue }
            let out = Set(excluded)
            claim.members[row.id] = tonight.filter { !out.contains($0) }
        }
        let smallLists = SubThemeRule.membersTonight(of: rows, claim: claim, moments: moments, photosById: photos,
                                                     calendar: calendar)
        return rows.map { original in
            var row = original
            let movable = row.status == .active || row.status == .frozen
            switch row.kind {
            case .big:
                row.followRatio = claim.ratios[row.id]
                row.flagged = claim.flagged.contains(row.id)
                row.members = claim.members[row.id] ?? row.members
                if movable { row.status = claim.frozen.contains(row.id) ? .frozen : .active }
            case .small:
                row.members = smallLists[row.id] ?? row.members
                if movable, let parent = row.parentId {
                    row.status = claim.frozen.contains(parent) ? .frozen : .active
                }
            }
            return row
        }
    }
}
