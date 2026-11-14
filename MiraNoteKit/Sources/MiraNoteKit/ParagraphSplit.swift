import CoreGraphics

/// #184: words written in one go become one text block per paragraph once
/// the writing ends, stacked down the page in reading order.
public enum ParagraphSplit {
    /// The gap between the stacked blocks' frames, as Tidy spaces elements.
    public static let gap: CGFloat = 24

    /// `text` split into paragraphs on blank lines (lines holding nothing
    /// but spaces), empty ones dropped. A single line break stays inside
    /// its paragraph, so poems and lists keep their lines. Only trailing
    /// spaces are trimmed: a leading indent (two ideographic spaces opening
    /// Chinese prose, a list item's) is kept as written.
    public static func paragraphs(of text: String) -> [String] {
        var paragraphs: [String] = []
        var lines: [Substring] = []
        func close() {
            var paragraph = lines.joined(separator: "\n")
            while paragraph.last?.isWhitespace == true { paragraph.removeLast() }
            if !paragraph.isEmpty { paragraphs.append(paragraph) }
            lines = []
        }
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.allSatisfy(\.isWhitespace) {
                close()
            } else {
                lines.append(line)
            }
        }
        close()
        return paragraphs
    }

    /// The elements a split of `block` moves down, as the page was written:
    /// those starting under its bottom edge and sharing some of its width,
    /// and in a chain (as TextFit pushes) those under a moving element and
    /// sharing its width, top to bottom. An element beside the block, with
    /// nothing moving above it, stays.
    static func below(_ block: CanvasItem, in items: [CanvasItem]) -> Set<CanvasItem.ID> {
        func top(_ item: CanvasItem) -> CGFloat { item.position.y - item.size.height / 2 }
        func under(_ item: CanvasItem, _ above: CanvasItem) -> Bool {
            top(item) >= above.position.y + above.size.height / 2 - 0.5
                && abs(item.position.x - above.position.x) < (item.size.width + above.size.width) / 2
        }
        var moving: [CanvasItem] = []
        for item in items.filter({ $0.id != block.id }).sorted(by: { top($0) < top($1) })
        where under(item, block) || moving.contains(where: { under(item, $0) }) {
            moving.append(item)
        }
        return Set(moving.map(\.id))
    }

    /// `blocks` stacked under `anchor`, `gap` apart, at its x: the elements
    /// in `moving` move down by the room the stack takes, together, so
    /// their gaps and the gap under the anchor are kept and nothing new
    /// overlaps.
    static func stack(_ blocks: [CanvasItem], under anchor: CanvasItem, moving: Set<CanvasItem.ID>,
                      in items: [CanvasItem], gap: CGFloat) -> [CanvasItem] {
        let line = anchor.position.y + anchor.size.height / 2
        let room = blocks.reduce(0) { $0 + gap + $1.size.height }
        var page = items.map { item in
            var moved = item
            if moving.contains(item.id) { moved.position.y += room }
            return moved
        }
        var top = line
        for var block in blocks {
            top += gap
            block.position = CGPoint(x: anchor.position.x, y: top + block.size.height / 2)
            top += block.size.height
            page.append(block)
        }
        return page
    }
}
