import CoreGraphics
import XCTest
@testable import MiraNoteKit

/// #183: one-tap layout templates.
final class PageLayoutTests: XCTestCase {
    private typealias Template = PageLayout.Template
    private let width: CGFloat = 360
    private let lineHeight: (CanvasItem, CGFloat) -> CGFloat = { _, _ in 40 }
    private let aspect: (CanvasItem) -> CGFloat = { $0.size.height / $0.size.width }

    private static let portrait = CGSize(width: 90, height: 120)
    private static let landscape = CGSize(width: 160, height: 90)

    private func photo(_ n: Int, _ size: CGSize = CGSize(width: 160, height: 120)) -> CanvasItem {
        CanvasItem(content: .image(ImageRef(displayName: "p\(n)", frameName: "white")),
                   position: CGPoint(x: 100, y: 100 + CGFloat(n) * 200), size: size, rotation: 12)
    }

    private func words(_ text: String, y: CGFloat) -> CanvasItem {
        CanvasItem(content: .text(TextBlock(text: text, pointSize: 20, colorName: "forest", fontName: "Futura",
                                            backgroundColorName: "sand")),
                   position: CGPoint(x: 180, y: y), size: CGSize(width: 200, height: 40))
    }

    private func page(photos: Int, texts: Int = 2, stickers: Int = 0,
                      shape: (Int) -> CGSize = { _ in CGSize(width: 160, height: 120) }) -> [CanvasItem] {
        (0..<photos).map { photo($0, shape($0)) }
            + (0..<texts).map { words("text \($0)", y: 50 + CGFloat($0) * 2000) }
            + (0..<stickers).map { _ in
                CanvasItem(content: .sticker(GeneratedSticker(prompt: "cup", symbolName: "cup.and.saucer.fill")),
                           position: CGPoint(x: 300, y: 3000), size: CGSize(width: 200, height: 200))
            }
    }

    /// Portrait and landscape in turn.
    private func mixed(photos: Int, texts: Int = 2, stickers: Int = 0) -> [CanvasItem] {
        page(photos: photos, texts: texts, stickers: stickers) { $0 % 2 == 0 ? Self.portrait : Self.landscape }
    }

    /// Every photo count a template is offered for.
    private func counts(_ template: Template) -> [Int] {
        template.photoCounts.map(Array.init) ?? Array(1...10)
    }

    private func frame(_ item: CanvasItem) -> CGRect {
        CGRect(x: item.position.x - item.size.width / 2, y: item.position.y - item.size.height / 2,
               width: item.size.width, height: item.size.height)
    }

    /// What is drawn for the item: a photo's frame around it, tilted.
    private func drawn(_ item: CanvasItem) -> CGRect {
        var box = frame(item)
        if case .image(let ref) = item.content {
            switch ref.frameName {
            case "white": box = box.insetBy(dx: -6, dy: -6)
            case "polaroid": box = box.insetBy(dx: -8, dy: -17)
            default: break
            }
        }
        let angle = abs(item.rotation) * .pi / 180
        let w = box.width * cos(angle) + box.height * sin(angle)
        let h = box.width * sin(angle) + box.height * cos(angle)
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    private func laid(_ template: Template, _ items: [CanvasItem]) -> [CanvasItem] {
        PageLayout.apply(template, to: items, pageWidth: width, textHeight: lineHeight, photoAspect: aspect)
    }

    private func photos(_ items: [CanvasItem]) -> [CanvasItem] { items.filter(\.content.isImage) }

    func testTheSixteenApprovedTemplates() {
        XCTAssertEqual(Template.allCases.map(\.rawValue), [
            "cover", "polaroid", "minimal", "stagger", "scrapbook", "onePlusTwo", "tShape",
            "grid2x2", "heroThree", "polaroidWall", "magazine", "journal", "nineGrid", "twinHero",
            "masonry", "strip",
        ])
    }

    func testOnlyTemplatesForThePhotoCountAreOffered() {
        func offered(_ count: Int) -> [Template] { PageLayout.templates(for: page(photos: count)) }
        XCTAssertEqual(offered(0), [.masonry, .strip])
        XCTAssertEqual(offered(1), [.cover, .polaroid, .minimal, .masonry, .strip])
        XCTAssertEqual(offered(2), [.stagger, .scrapbook, .masonry, .strip])
        XCTAssertEqual(offered(3), [.onePlusTwo, .tShape, .masonry, .strip])
        XCTAssertEqual(offered(4), [.grid2x2, .heroThree, .polaroidWall, .masonry, .strip])
        XCTAssertEqual(offered(5), [.magazine, .journal, .masonry, .strip])
        XCTAssertEqual(offered(6), [.magazine, .journal, .masonry, .strip])
        XCTAssertEqual(offered(7), [.nineGrid, .twinHero, .masonry, .strip])
        XCTAssertEqual(offered(9), [.nineGrid, .twinHero, .masonry, .strip])
        XCTAssertEqual(offered(10), [.masonry, .strip], "more than nine: only the any-count ones")
    }

    func testEveryElementStaysOnThePage() {
        for template in Template.allCases {
            for count in counts(template) {
                let items = mixed(photos: count, stickers: 2)
                let out = laid(template, items)
                XCTAssertEqual(Set(out.map(\.id)), Set(items.map(\.id)), "\(template) \(count)")
                for item in out {
                    let f = drawn(item)
                    XCTAssertGreaterThanOrEqual(f.minX, -0.5, "\(template) \(count)")
                    XCTAssertLessThanOrEqual(f.maxX, width + 0.5, "\(template) \(count)")
                    XCTAssertGreaterThanOrEqual(f.minY, 0, "\(template) \(count)")
                }
            }
        }
    }

    /// Each photo fills its cell: its box is the cell (the renderer crops
    /// the picture to it), whatever the photo's own shape.
    func testPhotosFillTheirCellsExactly() {
        let third = (320.0 - 16) / 3
        let cells: [(Template, Int, [CGSize])] = [
            (.cover, 1, [CGSize(width: 320, height: 400)]),
            (.polaroid, 1, [CGSize(width: 224, height: 224)]),
            (.minimal, 1, [CGSize(width: 160, height: 200)]),
            (.stagger, 2, Array(repeating: CGSize(width: 190, height: 240), count: 2)),
            (.scrapbook, 2, [CGSize(width: 180, height: 220), CGSize(width: 180, height: 150)]),
            (.onePlusTwo, 3, [CGSize(width: 188, height: 256)] + Array(repeating: CGSize(width: 124, height: 124), count: 2)),
            (.tShape, 3, [CGSize(width: 320, height: 180)] + Array(repeating: CGSize(width: 156, height: 156), count: 2)),
            (.grid2x2, 4, Array(repeating: CGSize(width: 156, height: 156), count: 4)),
            (.heroThree, 4, [CGSize(width: 320, height: 213)] + Array(repeating: CGSize(width: third, height: third), count: 3)),
            (.polaroidWall, 4, Array(repeating: CGSize(width: 128, height: 128), count: 4)),
            (.magazine, 6, [CGSize(width: 188, height: 240)] + Array(repeating: CGSize(width: 124, height: 116), count: 2)
                + Array(repeating: CGSize(width: third, height: third), count: 3)),
            (.magazine, 5, [CGSize(width: 188, height: 240)] + Array(repeating: CGSize(width: 124, height: 116), count: 2)
                + Array(repeating: CGSize(width: 156, height: 120), count: 2)),
            (.journal, 5, Array(repeating: CGSize(width: 176, height: 132), count: 5)),
            (.nineGrid, 9, Array(repeating: CGSize(width: third, height: third), count: 9)),
            (.nineGrid, 7, Array(repeating: CGSize(width: third, height: third), count: 7)),
            (.twinHero, 9, Array(repeating: CGSize(width: 212, height: 212), count: 2)
                + Array(repeating: CGSize(width: 100, height: 102), count: 4)
                + Array(repeating: CGSize(width: third, height: third), count: 3)),
            (.twinHero, 7, Array(repeating: CGSize(width: 212, height: 212), count: 2)
                + Array(repeating: CGSize(width: 100, height: 102), count: 4) + [CGSize(width: 320, height: third)]),
            (.masonry, 6, [CGSize(width: 156, height: 208), CGSize(width: 156, height: 156), CGSize(width: 156, height: 180),
                           CGSize(width: 156, height: 156), CGSize(width: 156, height: 208), CGSize(width: 156, height: 180)]),
            (.strip, 6, Array(repeating: CGSize(width: 320, height: 200), count: 2)
                + Array(repeating: CGSize(width: 158, height: 158), count: 4)),
            (.strip, 2, Array(repeating: CGSize(width: 320, height: 200), count: 2)),
        ]
        func key(_ size: CGSize) -> String { String(format: "%.1fx%.1f", size.width, size.height) }
        for (template, count, expected) in cells {
            let sizes = photos(laid(template, mixed(photos: count))).map { key($0.size) }.sorted()
            XCTAssertEqual(sizes, expected.map(key).sorted(), "\(template) \(count)")
        }
    }

    func testPhotoFramesAreSetAsSpecified() {
        let expected: [Template: String] = [
            .cover: "", .polaroid: "polaroid", .minimal: "soft", .stagger: "white", .scrapbook: "white",
            .onePlusTwo: "soft", .tShape: "soft", .grid2x2: "soft", .heroThree: "soft",
            .polaroidWall: "polaroid", .magazine: "soft", .journal: "white", .nineGrid: "soft",
            .twinHero: "soft", .masonry: "soft", .strip: "soft",
        ]
        for template in Template.allCases {
            let count = counts(template).last!
            let frames = Set(photos(laid(template, page(photos: count))).map(\.content.frameName))
            XCTAssertEqual(frames, [expected[template]!], "\(template)")
        }
    }

    func testOnlyTheFreeformTemplatesTiltOrOverlapPhotos() {
        let tilted: Set<Template> = [.polaroid, .stagger, .scrapbook, .polaroidWall, .journal]
        let overlapping: Set<Template> = [.stagger, .scrapbook]
        for template in Template.allCases {
            let shots = photos(laid(template, page(photos: counts(template).last!)))
            let overlaps = shots.indices.contains { a in
                shots.indices.contains { b in a < b && drawn(shots[a]).insetBy(dx: 1, dy: 1).intersects(drawn(shots[b])) }
            }
            XCTAssertEqual(shots.contains { $0.rotation != 0 }, tilted.contains(template), "\(template)")
            if overlapping.contains(template) {
                XCTAssertTrue(overlaps, "\(template)")
            } else if !tilted.contains(template) {
                XCTAssertFalse(overlaps, "\(template)")
            }
        }
        let stagger = photos(laid(.stagger, page(photos: 2))).sorted { $0.position.y < $1.position.y }
        XCTAssertGreaterThan(stagger[1].zIndex, stagger[0].zIndex, "the lower photo lies on the upper one")
    }

    func testTextNeverOverlapsAPhotoAndKeepsItsStyle() {
        for template in Template.allCases {
            for count in counts(template) {
                let items = mixed(photos: count, texts: 3)
                let out = laid(template, items)
                for text in out where text.content.text != nil {
                    for shot in photos(out) {
                        XCTAssertFalse(frame(text).insetBy(dx: 1, dy: 1).intersects(drawn(shot)),
                                       "\(template) \(count) \(text.content.text!)")
                    }
                    let before = items.first { $0.id == text.id }!.content.block!
                    let after = text.content.block!
                    XCTAssertEqual([after.text, after.colorName, after.fontName, after.backgroundColorName],
                                   [before.text, before.colorName, before.fontName, before.backgroundColorName])
                    XCTAssertEqual(after.pointSize, before.pointSize)
                }
            }
        }
    }

    func testNarrowAndCenteredTextWhereTheMockupShowsIt() {
        func texts(_ template: Template, _ count: Int) -> [CanvasItem] {
            laid(template, page(photos: count)).filter { $0.content.text != nil }.sorted { $0.position.y < $1.position.y }
        }
        let minimal = texts(.minimal, 1)
        XCTAssertEqual(minimal.map(\.size.width), [220, 220])
        XCTAssertTrue(minimal.allSatisfy { $0.content.block?.alignment == .center && $0.position.x == 180 })
        XCTAssertGreaterThan(minimal[0].position.y, photos(laid(.minimal, page(photos: 1)))[0].position.y,
                             "the title sits under the photo")
        XCTAssertEqual(texts(.polaroid, 1).map(\.size.width), [320, 260])
        let journal = texts(.journal, 5)
        XCTAssertEqual(journal.map(\.size.width), [320, 120], "the title across, the words in the side column")
        XCTAssertEqual(texts(.cover, 1).map { $0.content.block!.alignment }, [.leading, .leading],
                       "templates that do not center leave the alignment as it was")
    }

    func testJournalPhotosWithoutWordsBesideThemAreCenteredAndStraight() {
        let shots = photos(laid(.journal, page(photos: 5))).sorted { $0.position.y < $1.position.y }
        XCTAssertNotEqual(shots[0].position.x, 180, "the first photo has the words beside it")
        XCTAssertNotEqual(shots[0].rotation, 0)
        for shot in shots.dropFirst() {
            XCTAssertEqual(shot.position.x, 180)
            XCTAssertEqual(shot.rotation, 0)
        }
    }

    /// The most portrait photo takes the tallest cell and the most
    /// landscape the widest, so faces are cut the least.
    func testPhotosGoToCellsByOrientation() {
        let shaped: [Template] = [.scrapbook, .onePlusTwo, .tShape, .heroThree, .magazine, .twinHero, .strip]
        for template in shaped {
            let count = counts(template).last!
            // The portrait photo last in reading order, the landscape first.
            let items = page(photos: count) {
                $0 == count - 1 ? Self.portrait : $0 == 0 ? Self.landscape : CGSize(width: 100, height: 100)
            }
            let out = photos(laid(template, items))
            let shape = { (item: CanvasItem) in item.size.height / item.size.width }
            let cell = { (name: String) in shape(out.first { $0.content.name == name }!) }
            XCTAssertEqual(cell("p\(count - 1)"), out.map(shape).max()!, "\(template): portrait in the tallest")
            XCTAssertEqual(cell("p0"), out.map(shape).min()!, "\(template): landscape in the widest")
        }
    }

    func testPhotosOfOneShapeKeepTheirReadingOrder() {
        let shots = photos(laid(.tShape, page(photos: 3) { _ in CGSize(width: 100, height: 100) }))
            .sorted { ($0.position.y, $0.position.x) < ($1.position.y, $1.position.x) }
        XCTAssertEqual(shots.map(\.content.name), ["p0", "p1", "p2"])
    }

    func testStickersSitOnPhotoCornersAtMost80Points() {
        let out = laid(.grid2x2, page(photos: 4, stickers: 5))
        let shots = photos(out).map(frame)
        let stickers = out.filter(\.content.isSticker)
        XCTAssertTrue(stickers.allSatisfy { max($0.size.width, $0.size.height) <= 80.5 })
        let onCorner = stickers.filter { s in shots.contains { $0.contains(s.position) } }
        XCTAssertEqual(onCorner.count, 4, "one per photo; the fifth stacks below")
    }

    func testTapeTemplatesUseTheStickersAsTape() {
        let scrapbook = laid(.scrapbook, page(photos: 2, stickers: 3)).filter(\.content.isSticker)
        XCTAssertEqual(scrapbook.map { max($0.size.width, $0.size.height).rounded() }.sorted(), [56, 56, 70])
        XCTAssertEqual(Set(scrapbook.map(\.rotation)), [-8, 40, -38])
        let wall = laid(.polaroidWall, page(photos: 4, stickers: 2)).filter(\.content.isSticker)
        XCTAssertEqual(wall.map { $0.size.width.rounded() }, [40, 40])
        XCTAssertEqual(wall.map(\.rotation), [-8, 10])
        func places(_ items: [CanvasItem]) -> [String] {
            photos(items).map { "\($0.content.name) \($0.position) \($0.size)" }.sorted()
        }
        XCTAssertEqual(places(laid(.scrapbook, page(photos: 2, stickers: 3))), places(laid(.scrapbook, page(photos: 2))),
                       "no stickers: the photos go the same way, without tape")
    }

    @MainActor func testKeepingALayoutIsOneUndoStep() {
        let editor = CanvasViewModel(memory: Memory())
        editor.previewLayout(page(photos: 2))
        let original = editor.memory.items
        let depth = editor.undoDepth
        editor.previewLayout(laid(.stagger, original))
        editor.previewLayout(laid(.masonry, original))
        XCTAssertEqual(editor.undoDepth, depth, "trying templates adds no steps")
        editor.commitLayout(from: original)
        XCTAssertEqual(editor.undoDepth, depth + 1)
        XCTAssertEqual(editor.memory.items, laid(.masonry, original))
        editor.undo()
        XCTAssertEqual(editor.memory.items, original)
    }

    @MainActor func testCancellingLeavesThePageAndHistoryAsTheyWere() {
        let editor = CanvasViewModel(memory: Memory())
        editor.previewLayout(page(photos: 2))
        let original = editor.memory.items
        let depth = editor.undoDepth
        editor.previewLayout(laid(.scrapbook, original))
        editor.previewLayout(original)
        editor.commitLayout(from: original)
        XCTAssertEqual(editor.memory.items, original)
        XCTAssertEqual(editor.undoDepth, depth, "nothing kept, nothing to undo")
    }
}

private extension CanvasItem.Content {
    var isImage: Bool { if case .image = self { return true }; return false }
    var isSticker: Bool { if case .sticker = self { return true }; return false }
    var block: TextBlock? { if case .text(let block) = self { return block }; return nil }
    var text: String? { block?.text }
    var frameName: String { if case .image(let ref) = self { return ref.frameName }; return "-" }
    var name: String { if case .image(let ref) = self { return ref.displayName }; return "-" }
}
