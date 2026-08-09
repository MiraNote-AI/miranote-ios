import CoreGraphics
import Foundation

public extension CanvasViewModel {
    /// Apply one turn's worth of Mira edits as a single change.
    ///
    /// Takes exactly one snapshot and then mutates `memory.items`
    /// directly. It deliberately does NOT call `setTextPointSize`,
    /// `setTextColorName`, `bringToFront` or `sendToBack`: each of those
    /// snapshots itself, and `revert()` pops only one, so routing through
    /// them would leave Revert undoing a fraction of what the receipt
    /// claims.
    ///
    /// Order matters. Point sizes land first and the text box is
    /// re-measured before positions are applied, because Mira computed
    /// its coordinates against the heights it was shown -- changing a
    /// size first would silently invalidate every position below it.
    ///
    /// Returns false when nothing landed, so the caller can show a
    /// clarify card instead of a receipt for a change that never was.
    @discardableResult
    func applyPageEdits(_ changes: [ResolvedChange]) -> Bool {
        let live = changes.filter { index(of: $0.id) != nil }
        guard !live.isEmpty else { return false }

        beginChange()

        // 1. Style, and 2. re-measure, in one pass per element.
        for change in live {
            guard let itemIndex = index(of: change.id),
                  case .text(var block) = memory.items[itemIndex].content else { continue }
            var touched = false
            if let pointSize = change.pointSize {
                block.pointSize = pointSize
                touched = true
            }
            if let colorName = change.colorName {
                block.colorName = colorName
                touched = true
            }
            guard touched else { continue }
            memory.items[itemIndex].content = .text(block)
            guard change.pointSize != nil else { continue }
            // Same pairing the existing resize intent always makes: a
            // point size without a re-measure clips the text.
            let measured = max(36, Memory.estimatedTextHeight(
                block.text,
                pointSize: block.pointSize,
                width: memory.items[itemIndex].size.width
            ))
            let old = memory.items[itemIndex].size.height
            memory.items[itemIndex].size.height = measured
            memory.items[itemIndex].position.y += (measured - old) / 2
        }

        // 3. Geometry and stacking, against boxes that are now honest.
        for change in live {
            guard let itemIndex = index(of: change.id) else { continue }
            if let w = change.w {
                memory.items[itemIndex].size.width = max(44, CGFloat(w))
            }
            if let h = change.h {
                memory.items[itemIndex].size.height = max(36, CGFloat(h))
            }
            let size = memory.items[itemIndex].size
            if let x = change.x {
                memory.items[itemIndex].position.x = CGFloat(x) + size.width / 2
            }
            if let y = change.y {
                memory.items[itemIndex].position.y = CGFloat(y) + size.height / 2
            }
            switch change.layer {
            case .front: memory.items[itemIndex].zIndex = topZ + 1
            case .back: memory.items[itemIndex].zIndex = bottomZ - 1
            case nil: break
            }
        }
        return true
    }
}
