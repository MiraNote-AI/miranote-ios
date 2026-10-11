import Foundation
import MiraNoteKit

/// Decides which color-picker changes record an undo step. The system picker
/// streams a change per drag frame; one drag on one block's one property is
/// one step. A different block, a different property (color vs background),
/// a pause longer than the window, or a reset (the row closed, editing ended)
/// starts a new step.
struct PickerUndoGate {
    static let window: TimeInterval = 1.5

    private var last: (item: CanvasItem.ID, field: String, at: Date)?

    mutating func shouldRecord(item: CanvasItem.ID, field: String, now: Date = Date()) -> Bool {
        defer { last = (item, field, now) }
        guard let last,
              last.item == item,
              last.field == field,
              now.timeIntervalSince(last.at) <= Self.window else { return true }
        return false
    }

    mutating func reset() {
        last = nil
    }
}
