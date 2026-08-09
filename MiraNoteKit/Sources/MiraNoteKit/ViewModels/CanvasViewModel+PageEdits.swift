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
    /// The two passes are the order, not a style choice. Mira computed
    /// her coordinates against the heights she was shown, so a point size
    /// must land and the box be re-measured BEFORE anything is placed
    /// against it.
    ///
    /// Returns false when nothing landed, so the caller can show a
    /// clarify card instead of a receipt for a change that never was.
    @discardableResult
    func applyPageEdits(_ changes: [ResolvedChange]) -> Bool {
        let live = changes.filter { index(of: $0.id) != nil }
        guard !live.isEmpty else { return false }

        beginChange()
        for change in live { applyStyle(change) }
        for change in live { applyGeometry(change) }
        return true
    }
}

private extension CanvasViewModel {
    /// Point size and colour, then the re-measure the existing resize
    /// intent always pairs with -- a size without it clips the text.
    func applyStyle(_ change: ResolvedChange) {
        guard let itemIndex = index(of: change.id),
              case .text(var block) = memory.items[itemIndex].content else { return }
        if let pointSize = change.pointSize { block.pointSize = pointSize }
        if let colorName = change.colorName { block.colorName = colorName }
        guard change.pointSize != nil || change.colorName != nil else { return }
        memory.items[itemIndex].content = .text(block)

        guard change.pointSize != nil else { return }
        let measured = max(36, Memory.estimatedTextHeight(
            block.text,
            pointSize: block.pointSize,
            width: memory.items[itemIndex].size.width
        ))
        let old = memory.items[itemIndex].size.height
        memory.items[itemIndex].size.height = measured
        memory.items[itemIndex].position.y += (measured - old) / 2
    }

    /// Size, position and stacking, against boxes that are now honest.
    /// Coordinates arrive as top-left corners; the editor stores centers.
    func applyGeometry(_ change: ResolvedChange) {
        guard let itemIndex = index(of: change.id) else { return }
        if let width = change.w {
            memory.items[itemIndex].size.width = max(44, CGFloat(width))
        }
        if let height = change.h {
            memory.items[itemIndex].size.height = max(36, CGFloat(height))
        }
        let size = memory.items[itemIndex].size
        if let left = change.x {
            memory.items[itemIndex].position.x = CGFloat(left) + size.width / 2
        }
        if let top = change.y {
            memory.items[itemIndex].position.y = CGFloat(top) + size.height / 2
        }
        switch change.layer {
        case .front: memory.items[itemIndex].zIndex = topZ + 1
        case .back: memory.items[itemIndex].zIndex = bottomZ - 1
        case nil: break
        }
    }
}
