import Foundation

/// Picks a push's question once its night is fixed (handoff refine 4.3):
/// the backend sends up to three candidates, each with a type; the push
/// asks the first whose type no question fixed on the two nights before or
/// after it has (`other` never clashes). When every candidate clashes, the
/// first is asked and the clash goes in the run log.
///
/// Nights are picked one at a time, each seeing the picks already made:
/// seven groups answered together do not know of each other, so only the
/// phone can keep their questions apart.
public enum QuestionPicker {
    /// The type that never clashes, and the default of an untyped question.
    public static let otherType = "other"
    /// Nights either side whose question types a pick avoids.
    public static let reach = 2

    public struct Pick: Equatable, Sendable {
        public let question: TriggerMemory.Ending.Question
        /// Every candidate's type was taken nearby: the first was asked.
        public let clashed: Bool
    }

    /// The first candidate whose type is not in `nearby`; nil without candidates.
    public static func pick(_ candidates: [TriggerMemory.Ending.Question], nearby: [String]) -> Pick? {
        guard let first = candidates.first else { return nil }
        let taken = Set(nearby).subtracting([otherType, ""])
        if let free = candidates.first(where: { $0.type == otherType || !taken.contains($0.type) }) {
            return Pick(question: free, clashed: false)
        }
        return Pick(question: first, clashed: true)
    }

    /// `memory` asking its pick, and whether the pick clashed.
    public static func picking(_ memory: TriggerMemory, nearby: [String]) -> (memory: TriggerMemory, clashed: Bool) {
        guard let pick = pick(memory.ending.questions, nearby: nearby) else { return (memory, false) }
        return (memory.picking(pick.question), pick.clashed)
    }

    /// The question types fixed on the nights within `reach` of `night`'s
    /// day, `night` itself left out (its push is the one being replaced):
    /// one per night (the earliest push), in night order, so at most four.
    /// A push counts while it stands -- scheduled or delivered, not taken
    /// back, not dropped by iOS, not a debug push; one without a type
    /// (saved before types) does not.
    public static func nearbyTypes(_ entries: [LedgerEntry], around night: Date, calendar: Calendar) -> [String] {
        let day = calendar.startOfDay(for: night)
        var byOffset: [Int: LedgerEntry] = [:]
        for entry in entries where entry.removedAt == nil && entry.removedReason == nil
            && entry.notDeliveredReason == nil && !entry.isDebug {
            guard let type = entry.questionType, !type.isEmpty,
                  let offset = calendar.dateComponents([.day], from: day,
                                                       to: calendar.startOfDay(for: entry.scheduledFor)).day,
                  offset != 0, abs(offset) <= reach else { continue }
            if let held = byOffset[offset], held.scheduledFor <= entry.scheduledFor { continue }
            byOffset[offset] = entry
        }
        return byOffset.sorted { $0.key < $1.key }.compactMap(\.value.questionType)
    }
}
