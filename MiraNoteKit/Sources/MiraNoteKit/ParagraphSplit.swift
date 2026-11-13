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

    /// The elements a split of `block` moves down: those starting under its
    /// bottom edge, as it was written, and sharing some of its width (as
    /// TextFit pushes). An element beside the block stays.
    static func below(_ block: CanvasItem, in items: [CanvasItem]) -> Set<CanvasItem.ID> {
        let bottom = block.position.y + block.size.height / 2
        return Set(items.filter { item in
            item.id != block.id && item.position.y - item.size.height / 2 >= bottom - 0.5
                && abs(item.position.x - block.position.x) < (item.size.width + block.size.width) / 2
        }.map(\.id))
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
