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

    /// Two captions side by side, a full-width photo below both. Both grow
    /// (left by 40, right by 30): the photo moves by the larger, not the sum.
    func testSideBySideGrowthPushesByTheLargerGrowthNotTheSum() {
        let left = CanvasItem(content: .text(TextBlock(text: "left")), position: CGPoint(x: 100, y: 50),
                              size: CGSize(width: 160, height: 40))
        let right = CanvasItem(content: .text(TextBlock(text: "right")), position: CGPoint(x: 290, y: 50),
                               size: CGSize(width: 160, height: 40))
        let photo = CanvasItem(content: .image(ImageRef(displayName: "p")), position: CGPoint(x: 195, y: 194),
                               size: CGSize(width: 340, height: 200))
        let fitted = TextFit.apply(to: [left, right, photo]) { item in
            item.id == left.id ? 80 : (item.id == right.id ? 70 : nil)
        }
        XCTAssertEqual(top(fitted[2]) - top(photo), 40, accuracy: 0.5, "the photo moves by the larger growth")
    }

    /// A narrow caption above a wide photo; a sticker under the photo's
    /// right part (not under the caption) that the photo was clear of. The
    /// pushed photo pushes the sticker in turn.
    func testAPushedElementPushesWhatIsBelowItInTurn() {
        let caption = CanvasItem(content: .text(TextBlock(text: "c")), position: CGPoint(x: 80, y: 40),
                                 size: CGSize(width: 120, height: 40))
        // Photo: x 20...260, y 70...230.
        let photo = CanvasItem(content: .image(ImageRef(displayName: "p")), position: CGPoint(x: 140, y: 150),
                               size: CGSize(width: 240, height: 160))
        // Sticker: x 200...300, y 240...340.
        let sticker = CanvasItem(content: .sticker(GeneratedSticker(prompt: "s", symbolName: "sun.max")),
                                 position: CGPoint(x: 250, y: 290), size: CGSize(width: 100, height: 100))
        XCTAssertLessThan(bottom(photo), top(sticker))
        let fitted = TextFit.apply(to: [caption, photo, sticker]) { $0.id == caption.id ? 100 : nil }
        XCTAssertLessThanOrEqual(bottom(fitted[1]), top(fitted[2]), "the push drove the photo into the sticker")    }

    /// Writing grows the block live without moving anything (the page does
    /// not jump under the cursor); Done pushes what is below by the growth,
    /// in the session's own undo step.
    func testDonePushesWhatTheWritingGrewOverInTheSessionsStep() {
        let memory = page()
        let paragraph = memory.items[0].id, photo = memory.items[1].id
        let editor = CanvasViewModel(memory: memory)
        editor.startEditingText(paragraph)
        editor.setText(itemID: paragraph, to: "Sunny afternoon by the bridge, and then the long walk home")
        editor.autosizeTextHeight(itemID: paragraph, to: 90)
        XCTAssertEqual(top(editor.item(photo)), 112, accuracy: 0.5, "nothing moves while writing")

        editor.endEditingText()
        XCTAssertEqual(top(editor.item(photo)), 112 + 30, accuracy: 0.5, "Done pushes the photo by the 30 pt growth")
        XCTAssertGreaterThanOrEqual(top(editor.item(photo)), bottom(editor.item(paragraph)))

        editor.undo()
        XCTAssertEqual(editor.item(photo)?.position, memory.items[1].position, "one undo takes the push back too")
        XCTAssertEqual(editor.item(paragraph), memory.items[0])
        XCTAssertFalse(editor.canUndo, "the push is no step of its own")
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
