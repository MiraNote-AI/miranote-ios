import CoreGraphics
import Foundation

/// One-tap layouts (#183): fixed templates, Meitu-style, no model call. A
/// template sets where the page's photos, words and stickers go (position,
/// size, rotation, stacking, photo frame) and never how the words look:
/// font, size, color and background stay the user's. Geometry is drawn on
/// a 360-pt page (debug/templates-1109 mockup) and scales to the page.
public enum PageLayout {
    public enum Template: String, CaseIterable, Identifiable, Sendable {
        // One photo.
        /// The title, one large 4:5 photo, the words under it.
        case cover
        /// One tilted square polaroid, the words centered under it.
        case polaroid
        /// A small photo in a lot of white space, the words small and centered.
        case minimal
        // Two photos.
        /// Two white-framed photos overlapping, tilted opposite ways.
        case stagger
        /// One tall and one wide white-framed photo, the stickers as tape.
        case scrapbook
        // Three photos.
        /// One tall photo, two squares stacked beside it.
        case onePlusTwo
        /// One wide photo across, two squares under it.
        case tShape
        // Four photos.
        /// Four squares, two by two.
        case grid2x2
        /// One wide photo, three squares in a row under it.
        case heroThree
        /// Four small polaroids, each a little tilted, the stickers as tape.
        case polaroidWall
        // Five or six photos.
        /// A large photo, two beside it, a row under them.
        case magazine
        /// White-framed photos with the words in the column beside them.
        case journal
        // Seven to nine photos.
        /// Three by three squares; a short last row is centered.
        case nineGrid
        /// Two large photos on a diagonal, small ones around them.
        case twinHero
        // Any number of photos.
        /// Two columns of photos at staggered heights.
        case masonry
        /// Full-width and paired photos in turn, narrow seams.
        case strip

        public var id: String { rawValue }

        /// The photo counts the template is drawn for; nil: any count.
        /// Masonry takes two or more: one photo would be half a row.
        public var photoCounts: ClosedRange<Int>? {
            switch self {
            case .cover, .polaroid, .minimal: return 1...1
            case .stagger, .scrapbook: return 2...2
            case .onePlusTwo, .tShape: return 3...3
            case .grid2x2, .heroThree, .polaroidWall: return 4...4
            case .magazine, .journal: return 5...6
            case .nineGrid, .twinHero: return 7...9
            case .masonry: return 2...Int.max
            case .strip: return nil
            }
        }
    }

    /// The `ImageRef.frameName`s templates set; the app's `PhotoFrame` raw
    /// values. "" is the plain r18 photo.
    public enum Frame {
        public static let none = ""
        public static let white = "white"
        public static let polaroid = "polaroid"
        /// A small (r6) corner, for photos that sit in a grid.
        public static let soft = "soft"
    }

    static let margin: CGFloat = 20
    static let gap: CGFloat = 12
    static let top: CGFloat = 28
    /// The width the template geometry is drawn on.
    static let design: CGFloat = 360

    /// Layout is offered for a page with a photo and something else to
    /// arrange it with: words, stickers or a clip alone gain nothing.
    public static func isOffered(for items: [CanvasItem]) -> Bool {
        items.count >= 2 && photoCount(items) >= 1
    }

    /// The templates offered for these items: the ones drawn for their
    /// photo count, then the ones for any count.
    public static func templates(for items: [CanvasItem]) -> [Template] {
        let count = photoCount(items)
        return Template.allCases.filter { $0.photoCounts?.contains(count) ?? true }
    }

    /// Whether `a` and `b` are one arrangement: the same elements in the
    /// same places, sizes, tilts and looks. Stacking order is left out,
    /// as every layout restacks.
    public static func sameArrangement(_ a: [CanvasItem], _ b: [CanvasItem]) -> Bool {
        let others = Dictionary(b.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return a.count == b.count && a.allSatisfy { item in
            guard let other = others[item.id] else { return false }
            return item.content == other.content && abs(item.rotation - other.rotation) < 0.01
                && abs(item.position.x - other.position.x) < 0.5 && abs(item.position.y - other.position.y) < 0.5
                && abs(item.size.width - other.size.width) < 0.5 && abs(item.size.height - other.size.height) < 0.5
        }
    }

    private static func photoCount(_ items: [CanvasItem]) -> Int {
        items.filter { if case .image = $0.content { return true }; return false }.count
    }

    /// `items` placed by `template`. `textHeight` measures a text block at a
    /// width; `photoAspect` is a photo's real height over width, which
    /// decides its cell (the most portrait photo takes the tallest cell).
    /// Every element keeps its id and content; text keeps its style.
    public static func apply(_ template: Template, to items: [CanvasItem], pageWidth: CGFloat,
                             textHeight: @escaping (CanvasItem, CGFloat) -> CGFloat,
                             photoAspect: @escaping (CanvasItem) -> CGFloat) -> [CanvasItem] {
        var page = Page(items: items, scale: pageWidth / design, textHeight: textHeight, photoAspect: photoAspect)
        page.lay(template)
        page.placeStickers()
        page.stack(page.sounds)
        return page.items
    }
}

/// A photo's place in a template, in design points.
private struct Cell {
    var rect: CGRect
    var frame = PageLayout.Frame.soft
    var rotation: Double = 0

    init(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
         _ frame: String = PageLayout.Frame.soft, _ rotation: Double = 0) {
        rect = CGRect(x: x, y: y, width: width, height: height)
        self.frame = frame
        self.rotation = rotation
    }

    /// Height over width: the larger, the more portrait.
    var aspect: CGFloat { rect.height / max(rect.width, 1) }

    /// What the frame draws around the photo: the renderer pads it outside
    /// the photo's box and centers the whole on the box.
    var drawn: CGRect {
        switch frame {
        case PageLayout.Frame.white: return rect.insetBy(dx: -6, dy: -6)
        // 8 pt sides and top, 26 pt below: 34 pt more height, centered.
        case PageLayout.Frame.polaroid: return rect.insetBy(dx: -8, dy: -17)
        default: return rect
        }
    }

    /// `drawn` as tilted, as a box on the page.
    var bounds: CGRect {
        let box = drawn
        let angle = abs(rotation) * .pi / 180
        let width = box.width * cos(angle) + box.height * sin(angle)
        let height = box.width * sin(angle) + box.height * cos(angle)
        return CGRect(x: rect.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
    }
}

/// A place for a sticker as tape: its center (design points), its longest
/// side at most, its tilt.
private struct Spot {
    var center: CGPoint
    var side: CGFloat
    var rotation: Double
}

/// The page being laid out, top down from `next`.
private struct Page {
    var items: [CanvasItem]
    let scale: CGFloat
    let textHeight: (CanvasItem, CGFloat) -> CGFloat
    let photoAspect: (CanvasItem) -> CGFloat
    var next = PageLayout.top
    /// Where each placed photo landed, in cell order, for the stickers.
    var photoFrames: [CGRect] = []
    /// Template tape spots, on the page.
    var tape: [Spot] = []

    let photos: [CanvasItem.ID]
    let words: [CanvasItem.ID]
    let stickers: [CanvasItem.ID]
    let sounds: [CanvasItem.ID]

    init(items: [CanvasItem], scale: CGFloat, textHeight: @escaping (CanvasItem, CGFloat) -> CGFloat,
         photoAspect: @escaping (CanvasItem) -> CGFloat) {
        self.items = items
        self.scale = scale
        self.textHeight = textHeight
        self.photoAspect = photoAspect
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

    private var title: [CanvasItem.ID] { Array(words.prefix(1)) }
    private var rest: [CanvasItem.ID] { Array(words.dropFirst()) }
    /// A third of the inner width less two gutters: three squares across.
    private let third: CGFloat = (320 - 16) / 3

    private func index(_ id: CanvasItem.ID) -> Int { items.firstIndex { $0.id == id }! }

    // MARK: Templates

    mutating func lay(_ template: PageLayout.Template) {
        switch template {
        case .cover:
            place(words: title)
            fill([Cell(20, 84, 320, 400, PageLayout.Frame.none)])
            place(words: rest)
        case .polaroid:
            place(words: title, centered: true)
            fill([Cell(68, 84, 224, 224, PageLayout.Frame.polaroid, -3)])
            place(words: rest, x: 50, width: 260, centered: true)
        case .minimal:
            next = 96 * scale
            fill([Cell(100, 96, 160, 200)])
            next += PageLayout.gap
            // The mockup's 160/140 columns assume 18-pt words; the user's
            // own size stays, so the columns are 220.
            place(words: title, x: 70, width: 220, centered: true)
            place(words: rest, x: 70, width: 220, centered: true)
        case .stagger:
            place(words: title)
            fill([Cell(24, 84, 190, 240, PageLayout.Frame.white, -3),
                  Cell(146, 214, 190, 240, PageLayout.Frame.white, 4)])
            place(words: rest)
        case .scrapbook:
            place(words: title)
            let shift = fill([Cell(32, 92, 180, 220, PageLayout.Frame.white, -4),
                              Cell(150, 270, 180, 150, PageLayout.Frame.white, 3)])
            tape = [Spot(center: CGPoint(x: 118, y: 88), side: 70, rotation: -8),
                    Spot(center: CGPoint(x: 318, y: 272), side: 56, rotation: 40),
                    Spot(center: CGPoint(x: 158, y: 270), side: 56, rotation: -38)].map { shifted($0, by: shift) }
            place(words: rest)
        case .onePlusTwo:
            place(words: title)
            fill([Cell(20, 80, 188, 256), Cell(216, 80, 124, 124), Cell(216, 212, 124, 124)])
            place(words: rest)
        case .tShape:
            place(words: title)
            fill([Cell(20, 80, 320, 180), Cell(20, 268, 156, 156), Cell(184, 268, 156, 156)])
            place(words: rest)
        case .grid2x2:
            place(words: title, centered: true)
            fill([Cell(20, 80, 156, 156), Cell(184, 80, 156, 156),
                  Cell(20, 244, 156, 156), Cell(184, 244, 156, 156)])
            place(words: rest, x: 40, width: 280, centered: true)
        case .heroThree:
            place(words: title)
            fill([Cell(20, 80, 320, 213)] + row(y: 301, count: 3, height: third))
            place(words: rest)
        case .polaroidWall:
            place(words: title, centered: true)
            let frame = PageLayout.Frame.polaroid
            let shift = fill([Cell(34, 95, 128, 128, frame, -4), Cell(198, 105, 128, 128, frame, 3),
                              Cell(38, 275, 128, 128, frame, 2), Cell(194, 267, 128, 128, frame, -3)])
            tape = [Spot(center: CGPoint(x: 98, y: 86), side: 40, rotation: -8),
                    Spot(center: CGPoint(x: 262, y: 260), side: 40, rotation: 10)].map { shifted($0, by: shift) }
            place(words: rest, x: 40, width: 280, centered: true)
        case .magazine:
            place(words: title)
            let bottom = photos.count >= 6
                ? row(y: 328, count: 3, height: third)
                : row(y: 328, count: 2, height: 120)
            fill([Cell(20, 80, 188, 240), Cell(216, 80, 124, 116), Cell(216, 204, 124, 116)] + bottom)
            place(words: rest)
        case .journal:
            journal()
        case .nineGrid:
            place(words: title, centered: true)
            fill((0..<3).flatMap { line in
                row(y: 80 + CGFloat(line) * (third + 8), count: min(3, max(1, photos.count - line * 3)),
                    height: third, width: third)
            })
            place(words: rest, x: 40, width: 280, centered: true)
        case .twinHero:
            place(words: title)
            let middle = min(3, max(1, photos.count - 6))
            fill([Cell(20, 80, 212, 212), Cell(240, 80, 100, 102), Cell(240, 190, 100, 102)]
                 + row(y: 300, count: middle, height: third)
                 + [Cell(20, 409, 100, 102), Cell(20, 519, 100, 102), Cell(128, 409, 212, 212)])
            place(words: rest)
        case .masonry:
            place(words: title)
            fill(masonry(photos.count))
            place(words: rest)
        case .strip:
            place(words: title)
            fill(strip(photos.count, y: 80))
            place(words: rest)
        }
    }

    /// `count` cells `height` tall in a row at `y`, sharing the inner width
    /// (each `width` wide when given, the row centered).
    private func row(y: CGFloat, count: Int, height: CGFloat, width: CGFloat? = nil) -> [Cell] {
        let gutter: CGFloat = 8
        let cell = width ?? (320 - gutter * CGFloat(count - 1)) / CGFloat(count)
        let used = CGFloat(count) * cell + CGFloat(count - 1) * gutter
        let left = 20 + (320 - used) / 2
        return (0..<count).map { Cell(left + CGFloat($0) * (cell + gutter), y, cell, height) }
    }

    /// Two 156-pt columns, each cell going to the shorter one, at the
    /// mockup's staggered heights.
    private func masonry(_ count: Int) -> [Cell] {
        let heights: [[CGFloat]] = [[208, 156, 180], [156, 208, 180]]
        var bottoms: [CGFloat] = [0, 0], counts = [0, 0]
        return (0..<count).map { _ in
            let column = bottoms[1] < bottoms[0] ? 1 : 0
            let height = heights[column][counts[column] % 3]
            defer { bottoms[column] += height + 8; counts[column] += 1 }
            return Cell(20 + CGFloat(column) * 164, 80 + bottoms[column], 156, height)
        }
    }

    /// A full-width photo, then a pair, in turn, 4-pt seams; a pair short
    /// of its second photo is one full-width photo.
    private func strip(_ count: Int, y: CGFloat) -> [Cell] {
        var cells: [Cell] = [], top = y
        while cells.count < count {
            if cells.count % 3 == 0 || count - cells.count == 1 {
                cells.append(Cell(20, top, 320, 200))
                top += 204
            } else {
                cells += [Cell(20, top, 158, 158), Cell(182, top, 158, 158)]
                top += 162
            }
        }
        return cells
    }

    /// The title, then photos with a body block each in the column beside
    /// them, sides in turn, tops aligned; the photos left over two by two,
    /// and the words left over across. One body block, or words that would
    /// not fit the column (under ten characters a line, a word broken), go
    /// across under the photos instead.
    private mutating func journal() {
        place(words: title)
        let body = rest
        let photo = CGSize(width: 176, height: 132), column: CGFloat = 120
        let beside = body.count > 1 && body.allSatisfy { fits(items[index($0)], column: column) }
            ? min(body.count, photos.count) : 0
        for n in 0..<beside {
            let left = n % 2 == 0
            var cell = Cell(left ? 26 : 158, 0, photo.width, photo.height, PageLayout.Frame.white, left ? -2 : 2)
            let rowHeight = max(cell.bounds.height, textHeight(items[index(body[n])], column * scale) / scale)
            let top = next
            place(words: [body[n]], x: left ? 220 : 20, width: column)
            next = top
            cell.rect.origin.y = next / scale + (cell.rect.minY - cell.bounds.minY)
            put(photos[n], in: cell)
            next += rowHeight * scale + 20 * scale
        }
        let pairs = Array(photos.dropFirst(beside))
        fill(stride(from: 0, to: pairs.count, by: 2).flatMap { start -> [Cell] in
            let y = CGFloat(start / 2) * 140
            return pairs.count - start >= 2
                ? [Cell(26, y, 144, 108, PageLayout.Frame.white, -2), Cell(190, y, 144, 108, PageLayout.Frame.white, 2)]
                : [Cell((PageLayout.design - photo.width) / 2, y, photo.width, photo.height, PageLayout.Frame.white)]
        }, ids: pairs)
        place(words: Array(body.dropFirst(beside)))
    }

    /// Whether a text block reads well `column` design points wide: ten
    /// characters a line at its size, and no word broken.
    private func fits(_ item: CanvasItem, column: CGFloat) -> Bool {
        guard case .text(let block) = item.content else { return true }
        let width = column * scale
        guard width >= 10 * 0.55 * block.pointSize else { return false }
        guard let word = block.text.split(whereSeparator: \.isWhitespace).max(by: { $0.count < $1.count })
        else { return true }
        var alone = item, only = block
        only.text = String(word)
        alone.content = .text(only)
        return textHeight(alone, width) <= textHeight(alone, (PageLayout.design - 2 * PageLayout.margin) * scale)
    }

    // MARK: Placing

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

    private func page(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    /// The photo filling `cell` (the renderer crops it to the box), its
    /// frame set, stacked above everything placed before.
    private mutating func put(_ id: CanvasItem.ID, in cell: Cell) {
        var cell = cell
        if cell.frame == PageLayout.Frame.soft, case .image(let ref) = items[index(id)].content,
           [PageLayout.Frame.white, PageLayout.Frame.polaroid].contains(ref.frameName) {
            // A frame the user chose stays over the template's default
            // one; the photo shrinks so the frame fills the cell.
            let box = cell.rect
            cell.frame = ref.frameName
            let drawn = cell.drawn
            cell.rect = box.insetBy(dx: (drawn.width - box.width) / 2, dy: (drawn.height - box.height) / 2)
        }
        let rect = page(cell.rect)
        set(id, center: CGPoint(x: rect.midX, y: rect.midY), size: rect.size, rotation: cell.rotation)
        let i = index(id)
        if case .image(var ref) = items[i].content {
            ref.frameName = cell.frame
            items[i].content = .image(ref)
        }
        items[i].zIndex = (items.map(\.zIndex).max() ?? 0) + 1
        photoFrames.append(rect)
    }

    /// The photos in `cells`, moved down so the highest drawn edge sits at
    /// `next`: the most portrait photo in the tallest cell, the most
    /// landscape in the widest (ties in reading order). Photos beyond the
    /// cells continue below as a strip. Returns how far the cells moved
    /// down (design points).
    @discardableResult
    private mutating func fill(_ cells: [Cell], ids: [CanvasItem.ID]? = nil) -> CGFloat {
        let ids = ids ?? photos
        let used = Array(cells.prefix(ids.count))
        guard !used.isEmpty else { return 0 }
        let shift = next / scale - used.map(\.bounds.minY).min()!
        let byCell = used.indices.sorted { (used[$0].aspect, -$0) > (used[$1].aspect, -$1) }
        // To a hundredth: photos of one shape are one shape.
        let aspects = ids.map { (photoAspect(items[index($0)]) * 100).rounded() }
        let byPhoto = ids.indices.sorted { (aspects[$0], -$0) > (aspects[$1], -$1) }
        var cellOf: [Int: Int] = [:]
        for (cell, photo) in zip(byCell, byPhoto) { cellOf[photo] = cell }
        // Photos of one shape take their cells in reading order.
        for shape in Set(aspects) {
            let same = cellOf.keys.filter { aspects[$0] == shape }.sorted()
            for (photo, cell) in zip(same, same.map { cellOf[$0]! }.sorted()) { cellOf[photo] = cell }
        }
        var photoFor: [Int: CanvasItem.ID] = [:]
        for (photo, cell) in cellOf { photoFor[cell] = ids[photo] }
        for (n, var cell) in used.enumerated() {
            cell.rect.origin.y += shift
            put(photoFor[n]!, in: cell)
        }
        let placed = Set(photoFor.values)
        next = (used.map(\.bounds.maxY).max()! + shift) * scale + PageLayout.gap
        let extra = ids.filter { !placed.contains($0) }
        if !extra.isEmpty {
            fill(strip(extra.count, y: 0), ids: extra)
        }
        return shift
    }

    private func shifted(_ spot: Spot, by shift: CGFloat) -> Spot {
        Spot(center: CGPoint(x: spot.center.x * scale, y: (spot.center.y + shift) * scale),
             side: spot.side * scale, rotation: spot.rotation)
    }

    /// Text blocks `width` wide at `x` (design points; the inner width by
    /// default), one under the other, centered when the template centers
    /// them. Only the alignment of the block's own style changes.
    mutating func place(words ids: [CanvasItem.ID], x: CGFloat = PageLayout.margin,
                        width: CGFloat = PageLayout.design - 2 * PageLayout.margin, centered: Bool = false) {
        for id in ids {
            let i = index(id)
            if centered, case .text(var block) = items[i].content {
                block.alignment = .center
                items[i].content = .text(block)
            }
            let height = textHeight(items[i], width * scale)
            set(id, center: CGPoint(x: (x + width / 2) * scale, y: next + height / 2),
                size: CGSize(width: width * scale, height: height))
            next += height + PageLayout.gap
        }
    }

    /// Stickers on the template's tape spots first, then at most 80 pt on
    /// the photos' top-right corners, a little tilted; any left over stack.
    /// Where photos sit close (a grid's gutters), a sticker there would
    /// cover the neighbours: at most 56 pt on the grid's outer corners
    /// instead, half in the margin.
    mutating func placeStickers() {
        var corners = photoFrames.map { Spot(center: CGPoint(x: $0.maxX, y: $0.minY), side: 80, rotation: 8) }
        let close = photoFrames.indices.contains { a in
            photoFrames.indices.contains { b in
                a < b && photoFrames[a].insetBy(dx: -12 * scale, dy: -12 * scale).intersects(photoFrames[b])
            }
        }
        if close, let grid = photoFrames.dropFirst().reduce(photoFrames.first, { $0?.union($1) }) {
            let half = 28 * scale
            corners = [(grid.maxX, grid.minY + half, 8.0), (grid.minX, grid.maxY - half, -8),
                       (grid.maxX, grid.maxY - half, -6), (grid.minX, grid.minY + half, 6)].map {
                Spot(center: CGPoint(x: $0.0, y: $0.1), side: 56 * scale, rotation: $0.2)
            }
        }
        let spots = tape + corners
        var left: [CanvasItem.ID] = []
        for (n, id) in stickers.enumerated() {
            let size = items[index(id)].size
            let side = n < spots.count ? spots[n].side : 80
            let scale = min(1, side / max(size.width, size.height, 1))
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            guard n < spots.count else {
                items[index(id)].size = fitted
                left.append(id)
                continue
            }
            let spot = spots[n]
            var center = spot.center
            if n >= tape.count, !close {
                // Mostly on the photo, its corner poking out a little.
                center = CGPoint(x: spot.center.x - fitted.width * 0.2, y: spot.center.y + fitted.height * 0.2)
            }
            // Kept on the page as tilted.
            let angle = abs(spot.rotation) * .pi / 180
            let half = CGSize(width: (fitted.width * cos(angle) + fitted.height * sin(angle)) / 2,
                              height: (fitted.width * sin(angle) + fitted.height * cos(angle)) / 2)
            center.x = min(max(center.x, half.width), PageLayout.design * self.scale - half.width)
            center.y = max(center.y, half.height)
            set(id, center: center, size: fitted, rotation: spot.rotation)
            items[index(id)].zIndex = (items.map(\.zIndex).max() ?? 0) + 1
        }
        stack(left)
    }

    /// Elements as they are, centered, one under the other.
    mutating func stack(_ ids: [CanvasItem.ID]) {
        for id in ids {
            let size = items[index(id)].size
            set(id, center: CGPoint(x: PageLayout.design * scale / 2, y: next + size.height / 2), size: size)
            next += size.height + PageLayout.gap
        }
    }
}
