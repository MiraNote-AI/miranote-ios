import CoreGraphics

/// Text boxes fitted to their measured heights, top fixed. A box that grows
/// pushes the elements below it down by its growth -- those starting under
/// its old bottom edge and sharing some of its width -- so a grown block
/// (a page saved under the old padding, a longer Mira polish) never runs
/// under the next element. A pushed element pushes what is below it in
/// turn; one under several grown boxes moves by the largest push, not the
/// sum. A box that shrinks takes back what it pushed (its `clearance`),
/// never more, and never so far that a pulled element rises into another:
/// a box sized back and forth leaves the page where it started.
public enum TextFit {
    /// `height` gives a text box's new height, or nil to leave it as it is.
    public static func apply(to items: [CanvasItem], height: (CanvasItem) -> CGFloat?) -> [CanvasItem] {
        var fitted = items
        var reach = items
        // How far each element's cleared bottom edge moves by its own fit.
        var growth = [CGFloat](repeating: 0, count: items.count)
        for index in items.indices {
            let item = items[index]
            guard case .text = item.content, let new = height(item),
                  abs(new - item.size.height) > 0.5 else { continue }
            let cleared = clearedHeight(of: item, in: items)
            var pushed = item.clearance?.pushed ?? 0
            var nowCleared = new
            if new > cleared {
                growth[index] = new - cleared
                pushed += growth[index]
            } else {
                let back = min(pushed, cleared - new)
                growth[index] = -back
                pushed -= back
                nowCleared = cleared - back
            }
            fitted[index].position.y += (new - item.size.height) / 2
            fitted[index].size.height = new
            fitted[index].clearance = clearance(height: nowCleared, pushed: pushed, of: new)
            reach[index] = reaching(item, to: cleared)
        }
        return shifting(fitted, by: growth, over: reach)
    }

    /// The page with box `id` back to `origin` -- words, style, size and
    /// bookkeeping, its top where it is now -- and what its growth pushed
    /// since then taken back. Nothing else moves: whatever another action
    /// moved meanwhile stays. A nil `origin` takes the box off the page,
    /// with all it pushed; a box no longer on the page comes back as it was.
    static func revert(_ items: [CanvasItem], box id: CanvasItem.ID, to origin: CanvasItem?) -> [CanvasItem] {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return origin.map { items + [$0] } ?? items
        }
        let box = items[index]
        var growth = [CGFloat](repeating: 0, count: items.count)
        growth[index] = (origin?.clearance?.pushed ?? 0) - (box.clearance?.pushed ?? 0)
        var reach = items
        reach[index] = reaching(box, to: clearedHeight(of: box, in: items))
        var fitted = items
        if var restored = origin {
            restored.position = CGPoint(x: box.position.x, y: top(box) + restored.size.height / 2)
            fitted[index] = restored
        }
        fitted = shifting(fitted, by: growth, over: reach)
        if origin == nil { fitted.remove(at: index) }
        return fitted
    }

    /// Moves every element by what the boxes above it moved, top to bottom
    /// over the page as it was (`page`, boxes at their cleared heights): one
    /// pass reaches the fixpoint. A push takes the largest; a pull, only
    /// what keeps the element below everything above it.
    private static func shifting(_ items: [CanvasItem], by growth: [CGFloat], over page: [CanvasItem]) -> [CanvasItem] {
        var fitted = items
        var shift = [CGFloat](repeating: 0, count: page.count)
        let order = page.indices.sorted { top(page[$0]) < top(page[$1]) }
        for (rank, index) in order.enumerated() {
            var push: CGFloat = 0, pull: CGFloat = 0, floor = -CGFloat.infinity
            for above in order[..<rank] where top(page[index]) >= bottom(page[above]) - 0.5
                && sharesColumns(page[index], page[above]) {
                let moved = shift[above] + growth[above]
                push = max(push, moved)
                pull = min(pull, moved)
                floor = max(floor, bottom(page[above]) + moved - top(page[index]))
            }
            shift[index] = push > 0 ? push : max(pull, min(0, floor))
            fitted[index].position.y += shift[index]
        }
        return fitted
    }

    /// The height the elements below `item` clear: what its clearance
    /// says, but never past the room really left under it (an element
    /// moved up into the room a shrink left is pushed again).
    private static func clearedHeight(of item: CanvasItem, in items: [CanvasItem]) -> CGFloat {
        let height = item.size.height
        guard let kept = item.clearance?.height, kept > height else { return height }
        let room = items
            .filter { $0.id != item.id && top($0) >= bottom(item) - 0.5 && sharesColumns($0, item) }
            .map { max(0, top($0) - bottom(item)) }
            .min() ?? .infinity
        return min(kept, height + room)
    }

    /// Nil when there is nothing to remember.
    private static func clearance(height: CGFloat, pushed: CGFloat, of boxHeight: CGFloat) -> TextClearance? {
        pushed <= 0.5 && height <= boxHeight + 0.5 ? nil : TextClearance(height: height, pushed: max(0, pushed))
    }

    /// `item` drawn down to `height`, top fixed.
    private static func reaching(_ item: CanvasItem, to height: CGFloat) -> CanvasItem {
        var reached = item
        reached.position.y = top(item) + height / 2
        reached.size.height = height
        return reached
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
