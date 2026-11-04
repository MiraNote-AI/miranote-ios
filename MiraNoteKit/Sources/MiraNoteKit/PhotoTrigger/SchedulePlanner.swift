import Foundation

/// One night of the plan: what is already scheduled and who may take it.
public struct DayPlan: Equatable, Sendable {
    public let slot: Date
    /// The slot's calendar day, "yyyy-MM-dd" in the planning calendar.
    public let slotDay: String
    /// The active ledger entry scheduled for this calendar day.
    public let existing: LedgerEntry?
    /// The existing push fires within an hour: it stays, nothing replaces it.
    public let locked: Bool
    /// Candidates in pick order (empty when locked); the head is the plan.
    public let queue: [PushCandidate]
}

// swiftlint:disable function_parameter_count

/// Orders candidates for a night and lays them over the 7 nights.
public enum SchedulePlanner {
    /// No replacement this close to firing.
    public static let lockWindow: TimeInterval = 3600

    /// Drops taken groups and taken belongs-to days. After a push in
    /// another bucket the other buckets come first (`other` counts as
    /// different), then the same bucket, each by score; no previous bucket,
    /// or `other`, keeps plain score order.
    public static func queue(ranked: [PushCandidate], previousBucket: PushBucket?, takenGroups: Set<String>,
                             takenDays: Set<String>) -> [PushCandidate] {
        let open = ranked.filter { !takenGroups.contains($0.groupKey) && !takenDays.contains($0.belongsTo) }
        guard let previousBucket, previousBucket != .other else { return open }
        return open.filter { $0.bucket != previousBucket } + open.filter { $0.bucket == previousBucket }
    }

    /// Walks the slots in order; each night's head (or locked push) is
    /// taken for the nights after it, and its bucket steers the next pick.
    public static func plan(slots: [Date], rankedFor: (Date) -> [PushCandidate], active: [LedgerEntry],
                            lastDeliveredBucket: PushBucket?, now: Date, calendar: Calendar) -> [DayPlan] {
        var takenGroups: Set<String> = []
        var takenDays: Set<String> = []
        var previous = lastDeliveredBucket
        var plans: [DayPlan] = []
        for slot in slots {
            let existing = active.filter { $0.isActive && calendar.isDate($0.scheduledFor, inSameDayAs: slot) }
                .min { $0.scheduledFor < $1.scheduledFor }
            let locked = existing.map { $0.scheduledFor.timeIntervalSince(now) <= lockWindow } ?? false
            let queue = locked ? [] : Self.queue(ranked: rankedFor(slot), previousBucket: previous,
                                                 takenGroups: takenGroups, takenDays: takenDays)
            if locked, let existing {
                takenGroups.insert(existing.groupKey)
                takenDays.insert(existing.belongsTo)
                previous = existing.bucket
            } else if let head = queue.first {
                takenGroups.insert(head.groupKey)
                takenDays.insert(head.belongsTo)
                previous = head.bucket
            } else {
                previous = existing?.bucket
            }
            plans.append(DayPlan(slot: slot, slotDay: day(slot, calendar: calendar), existing: existing,
                                 locked: locked, queue: queue))
        }
        return plans
    }

    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
// swiftlint:enable function_parameter_count
