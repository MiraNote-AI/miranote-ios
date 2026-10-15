import MiraNoteKit
import UIKit
import XCTest
@testable import MiraNote

/// Pages drawn outside the editor (Reading, covers, exports, Mira's look)
/// show every line of text: a box saved under the old 6 pt padding grows
/// down to its measured height, as the editor would grow it.
@MainActor
final class StaticPageLayoutTests: XCTestCase {
    private func measured(_ item: CanvasItem) -> CGFloat? {
        guard case .text(let block) = item.content else { return nil }
        return TextMeasure.blockHeight(
            text: block.text, pointSize: block.pointSize, fontName: block.fontName, width: item.size.width
        )
    }

    func testEverySeededTextBlockFitsItsText() {
        let items = MemoryCollection.seed.flatMap(\.memories).flatMap(\.items)
        XCTAssertFalse(items.isEmpty)
        for item in items {
            guard let needed = measured(item), case .text(let block) = item.content else { continue }
            XCTAssertGreaterThanOrEqual(item.size.height, needed - 0.5, "'\(block.text)' is clipped")
        }
    }

    func testSeededElementsDoNotOverlap() {
        for memory in MemoryCollection.seed.flatMap(\.memories) {
            let frames = memory.items.map {
                CGRect(x: $0.position.x - $0.size.width / 2, y: $0.position.y - $0.size.height / 2,
                       width: $0.size.width, height: $0.size.height)
            }
            for (index, frame) in frames.enumerated() {
                for other in frames[(index + 1)...] {
                    XCTAssertFalse(frame.intersects(other), "\(memory.title): \(frame) overlaps \(other)")
                }
            }
        }
    }

    func testAShortSavedBoxIsDrawnAtItsMeasuredHeightGrowingDown() throws {
        let short = CanvasItem(
            content: .text(TextBlock(text: "Sunny afternoon, tiny noodle shop by the bridge, and then a long walk home",
                                     pointSize: 15)),
            position: CGPoint(x: 160, y: 100),
            size: CGSize(width: 288, height: 40)
        )
        let needed = try XCTUnwrap(measured(short))
        XCTAssertGreaterThan(needed, 40)

        let drawn = try XCTUnwrap(StaticPageView.laidOut(Memory(items: [short])).first)
        XCTAssertEqual(drawn.size.height, needed, accuracy: 0.5)
        XCTAssertEqual(drawn.position.y - drawn.size.height / 2, 80, accuracy: 0.5, "the top stays put")
    }

    /// A legacy page laid out by Tidy (24 pt gaps): a paragraph saved at its
    /// old height, then a photo added later. The grown paragraph must not
    /// run under the photo in Reading, covers or exports.
    func testAGrownLegacyBlockDoesNotRunUnderTheElementBelow() throws {
        let text = "Sunny afternoon, tiny noodle shop by the bridge. We sat by the window and watched "
            + "the boats go by while the broth cooled, and then walked home along the river."
        // The height TextMeasure gave before #105 (6 pt padding, no line spacing).
        let font = TextFace.uiFont(name: "", size: 15)
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat(288 - 12), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil
        )
        let height: CGFloat = max(36, ceil(bounds.height) + 20)
        let paragraph = CanvasItem(
            content: .text(TextBlock(text: text, pointSize: 15)),
            position: CGPoint(x: 195, y: 28 + height / 2), size: CGSize(width: 288, height: height), zIndex: 1
        )
        let photoTop = 28 + height + 24
        let photo = CanvasItem(
            content: .image(ImageRef(displayName: "photo")),
            position: CGPoint(x: 195, y: photoTop + 105), size: CGSize(width: 328, height: 210), zIndex: 2
        )
        let drawn = StaticPageView.laidOut(Memory(items: [paragraph, photo]))
        let grown = try XCTUnwrap(drawn.first { $0.id == paragraph.id })
        let moved = try XCTUnwrap(drawn.first { $0.id == photo.id })
        XCTAssertGreaterThan(grown.size.height, height, "the legacy box does grow")
        XCTAssertLessThanOrEqual(grown.position.y + grown.size.height / 2, moved.position.y - moved.size.height / 2,
                                 "grew \(grown.size.height - height) pt into the photo")
        XCTAssertEqual(moved.position.y - photo.position.y, grown.size.height - height, accuracy: 0.5,
                       "the photo moves down by the growth, keeping the 24 pt gap")
    }

    func testATallSavedBoxKeepsItsHeight() throws {
        let tall = CanvasItem(
            content: .text(TextBlock(text: "short", pointSize: 15)),
            position: CGPoint(x: 160, y: 100),
            size: CGSize(width: 288, height: 120)
        )
        let drawn = try XCTUnwrap(StaticPageView.laidOut(Memory(items: [tall])).first)
        XCTAssertEqual(drawn.size, tall.size)
        XCTAssertEqual(drawn.position, tall.position)
    }
}
