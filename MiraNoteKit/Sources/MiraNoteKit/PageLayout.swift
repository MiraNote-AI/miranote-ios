import CoreGraphics
import Foundation

/// One-tap layouts (#183): fixed templates, Meitu-style, no model call. A
/// template places the page's photos in slots, its words around them, and
/// stickers on the photos' corners. Reading order (top to bottom, then left
/// to right) decides which photo and which words go where.
public enum PageLayout {
    public enum Template: String, CaseIterable, Identifiable, Sendable {
        /// Words first, photos in a grid under them.
        case grid
        /// The title, a grid of photos, then the rest of the words.
        case titleGrid
        /// One large photo, the rest in a row under it.
        case hero
        /// Photo, words, photo, words: a diary column.
        case column
        /// Photos tilted and overlapping, left and right in turn.
        case collage

        public var id: String { rawValue }
    }

    static let margin: CGFloat = 20
    static let gap: CGFloat = 12
    static let top: CGFloat = 28

    /// The templates worth offering for these items: each one that places
    /// them differently from the ones before it (one photo has fewer).
    public static func templates(for items: [CanvasItem], pageWidth: CGFloat,
                                 textHeight: (CanvasItem, CGFloat) -> CGFloat) -> [Template] {
        var seen: [[CanvasItem]] = []
        return Template.allCases.filter { template in
            let laid = apply(template, to: items, pageWidth: pageWidth, textHeight: textHeight)
            guard !seen.contains(laid) else { return false }
            seen.append(laid)
            return true
        }
    }

    /// `items` placed by `template`. `textHeight` measures a text block at a
    /// width. Every element keeps its id, content and stacking order.
    public static func apply(_ template: Template, to items: [CanvasItem], pageWidth: CGFloat,
                             textHeight: (CanvasItem, CGFloat) -> CGFloat) -> [CanvasItem] {
        // Every text block runs the full inner width.
        let inner = pageWidth - 2 * margin
        var heights: [CanvasItem.ID: CGFloat] = [:]
        for item in items {
            if case .text = item.content { heights[item.id] = textHeight(item, inner) }
        }
        var page = Page(items: items, pageWidth: pageWidth, textHeights: heights)
        switch template {
        case .grid:
            page.place(words: page.words)
            page.grid(page.photos)
        case .titleGrid:
            page.place(words: Array(page.words.prefix(1)))
            page.grid(page.photos)
            page.place(words: Array(page.words.dropFirst()))
        case .hero:
            page.place(words: Array(page.words.prefix(1)))
            if let first = page.photos.first { page.row([first]) }
            page.grid(Array(page.photos.dropFirst()), columns: 3)
            page.place(words: Array(page.words.dropFirst()))
        case .column:
            page.column()
        case .collage:
            page.place(words: Array(page.words.prefix(1)))
            page.collage(page.photos)
            page.place(words: Array(page.words.dropFirst()))
        }
        page.stickOnCorners()
        page.stack(page.sounds)
        return page.items
    }
}

/// The page being laid out, top down from `next`.
private struct Page {
    var items: [CanvasItem]
    let width: CGFloat
    let textHeights: [CanvasItem.ID: CGFloat]
    var next = PageLayout.top
    /// Where each placed photo landed, for the stickers.
    var photoFrames: [CGRect] = []

    let photos: [CanvasItem.ID]
    let words: [CanvasItem.ID]
    let stickers: [CanvasItem.ID]
    let sounds: [CanvasItem.ID]

    init(items: [CanvasItem], pageWidth: CGFloat, textHeights: [CanvasItem.ID: CGFloat]) {
        self.items = items
        width = pageWidth
        self.textHeights = textHeights
        let reading = items.sorted {
            let a = $0.position.y - $0.size.height / 2, b = $1.position.y - $1.size.height / 2
            return abs(a - b) > 1 ? a < b : $0.position.x < $1.position.x
        }
        func ids(_ kind: (CanvasItem.Content) -> Bool) -> [CanvasItem.ID] {
            reading.filter { kind($0.content) }.map(\.id)
        }
        photos = ids { if case .image = $0 { return true }; return false }
        words = ids { if case .text = $0 { return true }; return false }
        stickers = ids { if case .sticker = $0 { return true }; return false }
        sounds = ids { if case .sound = $0 { return true }; return false }
    }

    private var inner: CGFloat { width - 2 * PageLayout.margin }

    private func index(_ id: CanvasItem.ID) -> Int { items.firstIndex { $0.id == id }! }

    /// Puts `id` with its center at `center`, at `size`, tilted `rotation`.
    private mutating func set(_ id: CanvasItem.ID, center: CGPoint, size: CGSize, rotation: Double = 0) {
        let i = index(id)
        items[i].position = center
        items[i].size = size
        items[i].rotation = rotation
        // A new layout: no earlier text push is left to take back.
        items[i].clearance = nil
        items[i].fitOffset = nil
    }

    /// The photo fitted inside `box`, keeping its shape, centered.
    private mutating func fit(_ id: CanvasItem.ID, in box: CGRect, rotation: Double = 0) {
        let size = items[index(id)].size
        let scale = min(box.width / max(size.width, 1), box.height / max(size.height, 1))
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        set(id, center: CGPoint(x: box.midX, y: box.midY), size: fitted, rotation: rotation)
        photoFrames.append(CGRect(x: box.midX - fitted.width / 2, y: box.midY - fitted.height / 2,
                                  width: fitted.width, height: fitted.height))
    }

    /// Text blocks full width, one under the other.
    mutating func place(words ids: [CanvasItem.ID]) {
        for id in ids {
            let height = textHeights[id] ?? items[index(id)].size.height
            set(id, center: CGPoint(x: width / 2, y: next + height / 2), size: CGSize(width: inner, height: height))
            next += height + PageLayout.gap
        }
    }

    /// One row of photos sharing the width, as tall as the shapes allow.
    mutating func row(_ ids: [CanvasItem.ID], maxHeight: CGFloat = 300) {
        guard !ids.isEmpty else { return }
        let cell = (inner - PageLayout.gap * CGFloat(ids.count - 1)) / CGFloat(ids.count)
        let height = min(maxHeight, ids.map { id -> CGFloat in
            let size = items[index(id)].size
            return cell * size.height / max(size.width, 1)
        }.max() ?? cell)
        for (n, id) in ids.enumerated() {
            let x = PageLayout.margin + CGFloat(n) * (cell + PageLayout.gap)
            fit(id, in: CGRect(x: x, y: next, width: cell, height: height))
        }
        next += height + PageLayout.gap
    }

    /// Square-ish cells, two across (three from five photos); a short last
    /// row is centered.
    mutating func grid(_ ids: [CanvasItem.ID], columns: Int? = nil) {
        guard !ids.isEmpty else { return }
        let across = columns ?? (ids.count == 1 ? 1 : ids.count <= 4 ? 2 : 3)
        let cell = (inner - PageLayout.gap * CGFloat(across - 1)) / CGFloat(across)
        let height = ids.count == 1 ? min(300, cell * 0.8) : cell
        for start in stride(from: 0, to: ids.count, by: across) {
            let rowIDs = Array(ids[start..<min(start + across, ids.count)])
            let used = CGFloat(rowIDs.count) * cell + CGFloat(rowIDs.count - 1) * PageLayout.gap
            let left = PageLayout.margin + (inner - used) / 2
            for (n, id) in rowIDs.enumerated() {
                fit(id, in: CGRect(x: left + CGFloat(n) * (cell + PageLayout.gap), y: next, width: cell, height: height))
            }
            next += height + PageLayout.gap
        }
    }

    /// Photo, then words, in turn; what is left of either follows.
    mutating func column() {
        let wide = inner * 0.86
        for n in 0..<max(photos.count, words.count) {
            if n < photos.count {
                let size = items[index(photos[n])].size
                let height = min(280, wide * size.height / max(size.width, 1))
                fit(photos[n], in: CGRect(x: (width - wide) / 2, y: next, width: wide, height: height))
                next += height + PageLayout.gap
            }
            if n < words.count { place(words: [words[n]]) }
        }
    }

    /// Photos at 58% of the width, left and right in turn, tilted and
    /// overlapping a little, each drawn over the one before.
    mutating func collage(_ ids: [CanvasItem.ID]) {
        let wide = inner * 0.58
        let tilts: [Double] = [-4, 3, -2, 4]
        var z = items.map(\.zIndex).max() ?? 0
        for (n, id) in ids.enumerated() {
            let size = items[index(id)].size
            let height = min(240, wide * size.height / max(size.width, 1))
            let x = n % 2 == 0 ? PageLayout.margin : width - PageLayout.margin - wide
            fit(id, in: CGRect(x: x, y: next, width: wide, height: height), rotation: tilts[n % tilts.count])
            z += 1
            items[index(id)].zIndex = z
            next += height * (n == ids.count - 1 ? 1 : 0.72) + (n == ids.count - 1 ? PageLayout.gap + 8 : 0)
        }
    }

    /// Stickers at most 80 pt, on the photos' top-right corners, a little
    /// tilted; with more stickers than photos, or no photos, they stack.
    mutating func stickOnCorners() {
        var left: [CanvasItem.ID] = []
        for (n, id) in stickers.enumerated() {
            let size = items[index(id)].size
            let scale = min(1, 80 / max(size.width, size.height, 1))
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            guard n < photoFrames.count else {
                items[index(id)].size = fitted
                left.append(id)
                continue
            }
            let frame = photoFrames[n]
            let center = CGPoint(x: min(frame.maxX - fitted.width * 0.2, width - fitted.width / 2),
                                 y: max(frame.minY + fitted.height * 0.2, fitted.height / 2))
            set(id, center: center, size: fitted, rotation: 8)
            items[index(id)].zIndex = (items.map(\.zIndex).max() ?? 0) + 1
        }
        stack(left)
    }

    /// Elements as they are, centered, one under the other.
    mutating func stack(_ ids: [CanvasItem.ID]) {
        for id in ids {
            let size = items[index(id)].size
            set(id, center: CGPoint(x: width / 2, y: next + size.height / 2), size: size)
            next += size.height + PageLayout.gap
        }
    }
}
