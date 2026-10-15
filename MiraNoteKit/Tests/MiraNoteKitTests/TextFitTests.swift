import XCTest
@testable import MiraNoteKit

/// A text box that grows to fit its words (a page saved under the old
/// padding, a longer Mira polish) pushes what sits below it down by the
/// growth, so its last lines never run under the next element.
@MainActor
final class TextFitTests: XCTestCase {
    private func top(_ item: CanvasItem?) -> CGFloat { (item?.position.y ?? 0) - (item?.size.height ?? 0) / 2 }
    private func bottom(_ item: CanvasItem?) -> CGFloat { (item?.position.y ?? 0) + (item?.size.height ?? 0) / 2 }

    /// A 60 pt paragraph at the top, a photo 24 below it, a sticker beside
    /// the paragraph (not below it) -- in that order.
    private func page() -> Memory {
        let paragraph = CanvasItem(
            content: .text(TextBlock(text: "Sunny afternoon by the bridge", pointSize: 15)),
            position: CGPoint(x: 150, y: 58), size: CGSize(width: 240, height: 60)
        )
        let photo = CanvasItem(
            content: .image(ImageRef(displayName: "photo")),
            position: CGPoint(x: 195, y: 112 + 105), size: CGSize(width: 328, height: 210), zIndex: 1
        )
        let sticker = CanvasItem(
            content: .sticker(GeneratedSticker(prompt: "sun", symbolName: "sun.max")),
            position: CGPoint(x: 330, y: 70), size: CGSize(width: 50, height: 50), zIndex: 2
        )
        return Memory(items: [paragraph, photo, sticker])
    }

    func testAGrownBlockPushesTheElementBelowDownByItsGrowth() {
        let memory = page()
        let paragraph = memory.items[0].id, photo = memory.items[1].id, sticker = memory.items[2].id
        let fitted = TextFit.apply(to: memory.items) { $0.id == paragraph ? 86 : nil }
        let text = fitted.first { $0.id == paragraph }
        let moved = fitted.first { $0.id == photo }
        XCTAssertEqual(top(text), 28, accuracy: 0.5, "the top stays put")
        XCTAssertEqual(bottom(text), 114, accuracy: 0.5)
        XCTAssertEqual(top(moved), 112 + 26, accuracy: 0.5, "the photo moves down by the 26 pt growth")
        XCTAssertGreaterThanOrEqual(top(moved), bottom(text), "the words no longer run under the photo")
        XCTAssertEqual(fitted.first { $0.id == sticker }?.position, memory.items[2].position,
                       "an element beside the block stays")
    }

    func testStackedBlocksThatBothGrowPushInTurn() {
        let first = CanvasItem(content: .text(TextBlock(text: "one")), position: CGPoint(x: 150, y: 50),
                               size: CGSize(width: 240, height: 40))
        let second = CanvasItem(content: .text(TextBlock(text: "two")), position: CGPoint(x: 150, y: 110),
                                size: CGSize(width: 240, height: 40))
        let photo = CanvasItem(content: .image(ImageRef(displayName: "photo")), position: CGPoint(x: 150, y: 250),
                               size: CGSize(width: 240, height: 160))
        let fitted = TextFit.apply(to: [first, second, photo]) { $0.id == photo.id ? nil : 60 }
        XCTAssertEqual(top(fitted[1]), 90 + 20, accuracy: 0.5, "the second block moves below the first's growth")
        XCTAssertEqual(top(fitted[2]), 170 + 40, accuracy: 0.5, "the photo moves by both growths")
    }

    func testRemeasuringInTheEditorPushesBelowAndRecordsNoStep() {
        let memory = page()
        let paragraph = memory.items[0].id, photo = memory.items[1].id
        let editor = CanvasViewModel(memory: memory)
        let count = editor.changeCount
        editor.fitTextHeights { $0.id == paragraph ? 86 : nil }
        XCTAssertEqual(top(editor.item(photo)), 112 + 26, accuracy: 0.5)
        XCTAssertEqual(editor.changeCount, count, "part of the remeasure, not an undo step of its own")
        XCTAssertFalse(editor.canUndo)
    }

    func testTheEditorStillShrinksABoxTallerThanItsWordsWithoutPullingOthersUp() {
        let memory = page()
        let paragraph = memory.items[0].id, photo = memory.items[1].id
        let editor = CanvasViewModel(memory: memory)
        editor.fitTextHeights { $0.id == paragraph ? 40 : nil }
        XCTAssertEqual(editor.item(paragraph)?.size.height ?? 0, 40, accuracy: 0.5)
        XCTAssertEqual(editor.item(photo)?.position, memory.items[1].position)
    }
}
