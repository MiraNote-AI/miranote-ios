import CoreGraphics
import Foundation

/// The palette names a canvas text block may persist in
/// `TextBlock.colorName`. The App layer resolves them to colors
/// (`Palette.color(named:)`); this list is the contract between the two,
/// and is also what Mira is offered to choose from -- the page map only
/// shows colors in USE, so a page of default text would otherwise leave
/// her inventing names like "warm beige".
public enum CanvasPalette {
    public static let names = ["ink", "onInk", "forest", "taupe", "tan", "sage"]
}

/// The page as Mira reads it: every element numbered, boxed, and
/// described. This is the source of truth for WHERE things are and HOW
/// BIG they are; the rendered image (look_at_page) only carries how the
/// page LOOKS.
public struct PageMap: Codable, Equatable, Sendable {
    public struct Element: Codable, Equatable, Sendable {
        public let handle: String
        public let kind: String
        public let x: Double
        public let y: Double
        public let w: Double
        public let h: Double
        public let says: String
        public let pointSize: Double?
        public let color: String?
        public let rotation: Double?
        public let treatment: String?

        enum CodingKeys: String, CodingKey {
            case handle, kind, x, y, w, h, says
            case pointSize = "point_size"
            case color, rotation, treatment
        }
    }

    public let width: Double
    public let height: Double
    public let background: String
    public let palette: [String]
    public let elements: [Element]
    public let omitted: Int
}

public extension PageMap {
    /// Past this the block stops being readable and starts being a token
    /// bill. The remainder is stated, never silently dropped.
    static let maxElements = 24

    /// Returns the map plus the handle -> item id table. The table stays
    /// on device: handles are per-turn, ids are forever.
    static func build(
        from memory: Memory, canvasWidth: CGFloat
    ) -> (map: PageMap, handles: [String: CanvasItem.ID]) {
        // Reading order, by top edge. The flat note form iterated the
        // array (creation order) despite claiming otherwise, so "the
        // first block" and "the one above it" never meant what the user
        // meant.
        let ordered = memory.items.sorted {
            $0.position.y - $0.size.height / 2 < $1.position.y - $1.size.height / 2
        }
        var counters: [String: Int] = [:]
        var handles: [String: CanvasItem.ID] = [:]
        var elements: [Element] = []

        for item in ordered.prefix(maxElements) {
            let kind = Self.kind(of: item)
            let prefix = Self.prefix(for: kind)
            let next = (counters[prefix] ?? 0) + 1
            counters[prefix] = next
            let handle = "\(prefix)\(next)"
            handles[handle] = item.id
            elements.append(Element(
                handle: handle,
                kind: kind,
                x: Double(item.position.x - item.size.width / 2),
                y: Double(item.position.y - item.size.height / 2),
                w: Double(item.size.width),
                h: Double(item.size.height),
                says: Self.says(of: item),
                pointSize: Self.pointSize(of: item),
                color: Self.color(of: item),
                rotation: item.rotation == 0 ? nil : item.rotation,
                treatment: Self.treatment(of: item)
            ))
        }

        let bottom = memory.items
            .map { $0.position.y + $0.size.height / 2 }
            .max() ?? 0
        let map = PageMap(
            width: Double(canvasWidth),
            height: Double(max(620, bottom + 120)),
            background: memory.backgroundFileName.isEmpty
                ? "default gradient" : "a picked backdrop image",
            palette: CanvasPalette.names,
            elements: elements,
            omitted: max(0, memory.items.count - elements.count)
        )
        return (map, handles)
    }

    private static func kind(of item: CanvasItem) -> String {
        switch item.content {
        case .text: return "text"
        case .image: return "photo"
        case .sticker: return "sticker"
        case .sound: return "sound"
        }
    }

    private static func prefix(for kind: String) -> String {
        switch kind {
        case "text": return "t"
        case "photo": return "p"
        case "sticker": return "s"
        default: return "a"
        }
    }

    private static func says(of item: CanvasItem) -> String {
        switch item.content {
        case .text(let block):
            return block.text
        case .image(let ref):
            // Same honesty as the flat note form: a file name would send
            // the model chasing bookshelves.
            return ref.summary.isEmpty
                ? "a photo Mira has not looked at yet" : ref.summary
        case .sticker(let sticker):
            return sticker.prompt
        case .sound(let clip):
            return clip.note
        }
    }

    private static func pointSize(of item: CanvasItem) -> Double? {
        guard case .text(let block) = item.content else { return nil }
        return Double(block.pointSize)
    }

    private static func color(of item: CanvasItem) -> String? {
        guard case .text(let block) = item.content,
              block.colorName != "ink", !block.colorName.isEmpty else { return nil }
        return block.colorName
    }

    private static func treatment(of item: CanvasItem) -> String? {
        guard case .image(let ref) = item.content else { return nil }
        let marks = [ref.filterName, ref.frameName].filter { !$0.isEmpty }
        return marks.isEmpty ? nil : marks.joined(separator: " ")
    }
}
