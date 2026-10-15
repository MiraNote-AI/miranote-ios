import CoreGraphics

/// Text boxes fitted to their measured heights, top fixed. A box that grows
/// pushes the elements below it down by its growth -- those starting under
/// its old bottom edge and sharing some of its width -- so a grown block
/// (a page saved under the old padding, a longer Mira polish) never runs
/// under the next element. A pushed element pushes what is below it in
/// turn; one under several grown boxes moves by the largest push, not the
/// sum. A box that shrinks pulls nothing up.
public enum TextFit {
    /// `height` gives a text box's new height, or nil to leave it as it is.
    public static func apply(to items: [CanvasItem], height: (CanvasItem) -> CGFloat?) -> [CanvasItem] {
        var fitted = items
        // How far each element's bottom edge moves down by its own fit.
        var growth = [CGFloat](repeating: 0, count: items.count)
        for index in items.indices {
            let item = items[index]
            guard case .text = item.content, let new = height(item),
                  abs(new - item.size.height) > 0.5 else { continue }
            growth[index] = new - item.size.height
            fitted[index].position.y += growth[index] / 2
            fitted[index].size.height = new
        }
        // Top to bottom over the page as it was: everything an element sits
        // under is settled before it, so one pass reaches the fixpoint.
        var shift = [CGFloat](repeating: 0, count: items.count)
        let order = items.indices.sorted { top(items[$0]) < top(items[$1]) }
        for (rank, index) in order.enumerated() {
            for above in order[..<rank] where top(items[index]) >= bottom(items[above]) - 0.5
                && sharesColumns(items[index], items[above]) {
                shift[index] = max(shift[index], shift[above] + growth[above])
            }
            fitted[index].position.y += shift[index]
        }
        return fitted
    }

    private static func top(_ item: CanvasItem) -> CGFloat { item.position.y - item.size.height / 2 }

    private static func bottom(_ item: CanvasItem) -> CGFloat { item.position.y + item.size.height / 2 }

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
