import CoreGraphics

/// Text boxes fitted to their measured heights, top fixed. A box that grows
/// pushes the elements below it down by its growth -- those starting under
/// its old bottom edge and sharing some of its width -- so a grown block
/// (a page saved under the old padding, a longer Mira polish) never runs
/// under the next element. A box that shrinks pulls nothing up.
public enum TextFit {
    /// `height` gives a text box's new height, or nil to leave it as it is.
    public static func apply(to items: [CanvasItem], height: (CanvasItem) -> CGFloat?) -> [CanvasItem] {
        var items = items
        // Top to bottom, so a block pushed down by one above it grows (and
        // pushes) from where it now is.
        let order = items.indices.sorted { top(items[$0]) < top(items[$1]) }
        for index in order {
            let item = items[index]
            guard case .text = item.content, let new = height(item),
                  abs(new - item.size.height) > 0.5 else { continue }
            let oldBottom = top(item) + item.size.height
            let growth = new - item.size.height
            items[index].position.y += growth / 2
            items[index].size.height = new
            guard growth > 0 else { continue }
            for other in items.indices where other != index
                && top(items[other]) >= oldBottom - 0.5 && sharesColumns(items[other], item) {
                items[other].position.y += growth
            }
        }
        return items
    }

    private static func top(_ item: CanvasItem) -> CGFloat { item.position.y - item.size.height / 2 }

    private static func sharesColumns(_ lhs: CanvasItem, _ rhs: CanvasItem) -> Bool {
        abs(lhs.position.x - rhs.position.x) < (lhs.size.width + rhs.size.width) / 2
    }
}

extension CanvasViewModel {
    /// Every text box fitted to its measured height (`height`, nil to leave
    /// one as it is), as part of a remeasure: no undo step of its own.
    public func fitTextHeights(_ height: (CanvasItem) -> CGFloat?) {
        let fitted = TextFit.apply(to: memory.items, height: height)
        if fitted != memory.items { memory.items = fitted }
    }
}
