import CoreGraphics

/// Full-screen writing (#184): words written in one go become one text
/// block per line, stacked down the page in reading order.
public enum ParagraphSplit {
    /// The gap between the stacked blocks' frames, as Tidy spaces elements.
    public static let gap: CGFloat = 24

    /// `text` split into paragraphs, each trimmed, empty ones dropped. The
    /// app's rule is the default: every line break starts one (Notion
    /// style). `everyLine: false` splits on blank lines only (lines holding
    /// nothing but spaces), a single line break staying inside its
    /// paragraph.
    public static func paragraphs(of text: String, everyLine: Bool = true) -> [String] {
        var paragraphs: [String] = []
        var lines: [Substring] = []
        func close() {
            let paragraph = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty { paragraphs.append(paragraph) }
            lines = []
        }
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.allSatisfy(\.isWhitespace) {
                close()
            } else {
                lines.append(line)
                if everyLine { close() }
            }
        }
        close()
        return paragraphs
    }

    /// `blocks` stacked under `anchor`, `gap` apart, at its x: everything
    /// starting at or below the anchor's bottom edge moves down by the room
    /// the stack takes, together, so their gaps and the gap under the
    /// anchor are kept and nothing new overlaps.
    static func stack(_ blocks: [CanvasItem], under anchor: CanvasItem, in items: [CanvasItem],
                      gap: CGFloat) -> [CanvasItem] {
        let line = anchor.position.y + anchor.size.height / 2
        let room = blocks.reduce(0) { $0 + gap + $1.size.height }
        var page = items.map { item in
            var moved = item
            if item.id != anchor.id, item.position.y - item.size.height / 2 >= line - 0.5 {
                moved.position.y += room
            }
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
