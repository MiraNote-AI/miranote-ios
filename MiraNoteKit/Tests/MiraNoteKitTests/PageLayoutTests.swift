import CoreGraphics
import XCTest
@testable import MiraNoteKit

/// #183: one-tap layout templates.
final class PageLayoutTests: XCTestCase {
    private let width: CGFloat = 360
    private let lineHeight: (CanvasItem, CGFloat) -> CGFloat = { _, _ in 40 }

    private func photo(_ n: Int, _ size: CGSize = CGSize(width: 160, height: 120)) -> CanvasItem {
        CanvasItem(content: .image(ImageRef(displayName: "p\(n)")), position: CGPoint(x: 100, y: 100 + CGFloat(n) * 200),
                   size: size, rotation: 12)
    }

    private func words(_ text: String, y: CGFloat) -> CanvasItem {
        CanvasItem(content: .text(TextBlock(text: text, pointSize: 20, colorName: "ink")),
                   position: CGPoint(x: 180, y: y), size: CGSize(width: 200, height: 40))
    }

    private func page(photos: Int, texts: Int = 2, stickers: Int = 0) -> [CanvasItem] {
        (0..<photos).map { photo($0) }
            + (0..<texts).map { words("text \($0)", y: 50 + CGFloat($0) * 900) }
            + (0..<stickers).map { _ in
                CanvasItem(content: .sticker(GeneratedSticker(prompt: "cup", symbolName: "cup.and.saucer.fill")),
                           position: CGPoint(x: 300, y: 2000), size: CGSize(width: 200, height: 200))
            }
    }

    private func frame(_ item: CanvasItem) -> CGRect {
        CGRect(x: item.position.x - item.size.width / 2, y: item.position.y - item.size.height / 2,
               width: item.size.width, height: item.size.height)
    }

    private func laid(_ template: PageLayout.Template, _ items: [CanvasItem]) -> [CanvasItem] {
        PageLayout.apply(template, to: items, pageWidth: width, textHeight: lineHeight)
    }

    func testEveryTemplateKeepsEveryElementOnThePage() {
        for count in 1...8 {
            let items = page(photos: count, stickers: 2)
            for template in PageLayout.Template.allCases {
                let out = laid(template, items)
                XCTAssertEqual(Set(out.map(\.id)), Set(items.map(\.id)), "\(template) \(count)")
                for item in out {
                    let f = frame(item)
                    XCTAssertGreaterThanOrEqual(f.minX, -0.5, "\(template) \(count)")
                    XCTAssertLessThanOrEqual(f.maxX, width + 0.5, "\(template) \(count)")
                    XCTAssertGreaterThanOrEqual(f.minY, 0, "\(template) \(count)")
                }
            }
        }
    }

    func testPhotosKeepTheirShape() {
        let items = page(photos: 3)
        for template in PageLayout.Template.allCases {
            for item in laid(template, items) where item.content.isImage {
                XCTAssertEqual(item.size.width / item.size.height, 160.0 / 120.0, accuracy: 0.01, "\(template)")
            }
        }
    }

    func testOnlyTheCollageTiltsAndOverlapsPhotos() {
        let items = page(photos: 4)
        for template in PageLayout.Template.allCases {
            let photos = laid(template, items).filter(\.content.isImage)
            let overlaps = photos.indices.contains { a in
                photos.indices.contains { b in a < b && frame(photos[a]).insetBy(dx: 1, dy: 1).intersects(frame(photos[b])) }
            }
            if template == .collage {
                XCTAssertTrue(photos.contains { $0.rotation != 0 })
                XCTAssertTrue(overlaps)
            } else {
                XCTAssertTrue(photos.allSatisfy { $0.rotation == 0 }, "\(template)")
                XCTAssertFalse(overlaps, "\(template)")
            }
        }
    }

    func testWordsKeepTheirOrderAndNeverOverlapPhotos() {
        let items = page(photos: 3, texts: 3)
        for template in PageLayout.Template.allCases {
            let out = laid(template, items)
            let texts = out.filter { !$0.content.isImage && !$0.content.isSticker }
            XCTAssertEqual(texts.sorted { $0.position.y < $1.position.y }.compactMap(\.content.text),
                           ["text 0", "text 1", "text 2"], "\(template)")
            for text in texts {
                for photo in out.filter(\.content.isImage) {
                    XCTAssertFalse(frame(text).insetBy(dx: 1, dy: 1).intersects(frame(photo)), "\(template)")
                }
            }
        }
    }

    func testTheGridPutsTwoAcrossUpToFourPhotosThenThree() {
        func across(_ count: Int) -> Int {
            let photos = laid(.grid, page(photos: count)).filter(\.content.isImage)
            let firstRow = photos.map(\.position.y).min()!
            return photos.filter { abs($0.position.y - firstRow) < 1 }.count
        }
        XCTAssertEqual(across(1), 1)
        XCTAssertEqual(across(4), 2)
        XCTAssertEqual(across(5), 3)
        XCTAssertEqual(across(6), 3)
    }

    func testStickersSitOnPhotoCornersAtMost80Points() {
        let out = laid(.grid, page(photos: 2, stickers: 3))
        let photos = out.filter(\.content.isImage).map(frame)
        let stickers = out.filter(\.content.isSticker)
        XCTAssertTrue(stickers.allSatisfy { max($0.size.width, $0.size.height) <= 80.5 })
        let onCorner = stickers.filter { s in photos.contains { $0.contains(s.position) } }
        XCTAssertEqual(onCorner.count, 2, "one per photo; the third stacks below")
    }

    func testOnePhotoOffersOnlyTheTemplatesThatDiffer() {
        let one = PageLayout.templates(for: page(photos: 1, texts: 1), pageWidth: width, textHeight: lineHeight)
        let many = PageLayout.templates(for: page(photos: 4), pageWidth: width, textHeight: lineHeight)
        XCTAssertLessThan(one.count, many.count)
        XCTAssertEqual(many, PageLayout.Template.allCases)
    }

    @MainActor func testKeepingALayoutIsOneUndoStep() {
        let editor = CanvasViewModel(memory: Memory())
        editor.previewLayout(page(photos: 2))
        let original = editor.memory.items
        let depth = editor.undoDepth
        editor.previewLayout(laid(.collage, original))
        editor.previewLayout(laid(.grid, original))
        XCTAssertEqual(editor.undoDepth, depth, "trying templates adds no steps")
        editor.commitLayout(from: original)
        XCTAssertEqual(editor.undoDepth, depth + 1)
        XCTAssertEqual(editor.memory.items, laid(.grid, original))
        editor.undo()
        XCTAssertEqual(editor.memory.items, original)
    }

    @MainActor func testCancellingLeavesThePageAndHistoryAsTheyWere() {
        let editor = CanvasViewModel(memory: Memory())
        editor.previewLayout(page(photos: 2))
        let original = editor.memory.items
        let depth = editor.undoDepth
        editor.previewLayout(laid(.hero, original))
        editor.previewLayout(original)
        editor.commitLayout(from: original)
        XCTAssertEqual(editor.memory.items, original)
        XCTAssertEqual(editor.undoDepth, depth, "nothing kept, nothing to undo")
    }
}

private extension CanvasItem.Content {
    var isImage: Bool { if case .image = self { return true }; return false }
    var isSticker: Bool { if case .sticker = self { return true }; return false }
    var text: String? { if case .text(let block) = self { return block.text }; return nil }
}
