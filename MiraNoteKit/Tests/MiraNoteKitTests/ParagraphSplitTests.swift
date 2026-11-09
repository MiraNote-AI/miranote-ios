import XCTest
@testable import MiraNoteKit

/// Full-screen writing (#184): Done splits the words on every line break
/// into one block per line, stacked under the block being written.
@MainActor
final class ParagraphSplitTests: XCTestCase {
    private func top(_ item: CanvasItem?) -> CGFloat { (item?.position.y ?? 0) - (item?.size.height ?? 0) / 2 }
    private func bottom(_ item: CanvasItem?) -> CGFloat { (item?.position.y ?? 0) + (item?.size.height ?? 0) / 2 }

    /// 30 pt per line, as if every line wraps nowhere.
    private func height(_ block: TextBlock, _ width: CGFloat) -> CGFloat {
        CGFloat(block.text.split(separator: "\n").count) * 30 + 28
    }

    private func texts(_ editor: CanvasViewModel) -> [String] {
        editor.items.sorted { $0.position.y < $1.position.y }.compactMap {
            guard case .text(let block) = $0.content else { return nil }
            return block.text
        }
    }

    // MARK: Splitting

    func testEveryLineIsAParagraph() {
        XCTAssertEqual(ParagraphSplit.paragraphs(of: "one\ntwo\n\nthree"), ["one", "two", "three"])
    }

    func testLinesAreTrimmedAndBlankOnesDropped() {
        XCTAssertEqual(ParagraphSplit.paragraphs(of: "\n\n  one  \n \t \n\n   \n two\n\n"), ["one", "two"])
        XCTAssertEqual(ParagraphSplit.paragraphs(of: " \n\n \n"), [])
        XCTAssertEqual(ParagraphSplit.paragraphs(of: ""), [])
    }

    func testWindowsLineBreaksCountAsOne() {
        XCTAssertEqual(ParagraphSplit.paragraphs(of: "one\r\ntwo\r\n\r\nthree"), ["one", "two", "three"])
    }

    /// The other rule, one argument away.
    func testBlankLineRuleKeepsSingleBreaksInside() {
        XCTAssertEqual(ParagraphSplit.paragraphs(of: "one\ntwo\n\nthree\n\n \n\nfour", everyLine: false),
                       ["one\ntwo", "three", "four"])
    }

    // MARK: Placing

    /// A styled block being written at the top, a photo 40 below it, and a
    /// sticker beside the block.
    private func writingPage() -> (CanvasViewModel, block: CanvasItem.ID, photo: CanvasItem.ID, sticker: CanvasItem.ID) {
        let style = TextBlock(text: "draft", pointSize: 21, colorName: "#8B5962", fontName: "Josefin Sans",
                              alignment: .center, backgroundColorName: "#F1EBDD")
        let block = CanvasItem(content: .text(style), position: CGPoint(x: 150, y: 100),
                               size: CGSize(width: 230, height: 58))
        let photo = CanvasItem(content: .image(ImageRef(displayName: "photo")),
                               position: CGPoint(x: 160, y: 129 + 40 + 80), size: CGSize(width: 200, height: 160),
                               zIndex: 1)
        let sticker = CanvasItem(content: .sticker(GeneratedSticker(prompt: "sun", symbolName: "sun.max")),
                                 position: CGPoint(x: 330, y: 90), size: CGSize(width: 50, height: 50), zIndex: 2)
        let editor = CanvasViewModel(memory: Memory(items: [block, photo, sticker]))
        editor.startEditingText(block.id)
        return (editor, block.id, photo.id, sticker.id)
    }

    func testDoneStacksOneBlockPerParagraphInTheBlocksStyle() {
        let (editor, id, _, _) = writingPage()
        let new = editor.finishFullScreenWriting("first\nsecond\n\nthird", height: height)

        XCTAssertEqual(new.count, 2)
        XCTAssertNil(editor.editingTextItemID, "Done ends the writing")
        XCTAssertEqual(texts(editor), ["first", "second", "third"])
        guard case .text(let kept) = editor.item(id)?.content else { return XCTFail("the block stays") }
        let stack = [id] + new
        for (upper, lower) in zip(stack, stack.dropFirst()) {
            let a = editor.item(upper), b = editor.item(lower)
            XCTAssertEqual(top(b) - bottom(a), ParagraphSplit.gap, accuracy: 0.5, "directly below, a gap apart")
            XCTAssertEqual(b?.position.x, a?.position.x)
            XCTAssertEqual(b?.size.width, a?.size.width)
        }
        XCTAssertEqual(editor.item(new[0])?.size.height, 58, "measured")
        for newID in new {
            guard case .text(let block) = editor.item(newID)?.content else { return XCTFail("a text block") }
            XCTAssertEqual(block.pointSize, kept.pointSize)
            XCTAssertEqual(block.fontName, kept.fontName)
            XCTAssertEqual(block.colorName, kept.colorName)
            XCTAssertEqual(block.alignment, kept.alignment)
            XCTAssertEqual(block.backgroundColorName, kept.backgroundColorName)
        }
    }

    func testWhatIsBelowMovesDownKeepingItsGapAndWhatIsBesideStays() {
        let (editor, id, photo, sticker) = writingPage()
        let before = editor.item(sticker)?.position
        let new = editor.finishFullScreenWriting("first\n\nsecond\n\nthird", height: height)
        XCTAssertEqual(top(editor.item(photo)) - bottom(editor.item(new.last!)), 40, accuracy: 0.5,
                       "the photo keeps its gap under the last block")
        XCTAssertEqual(editor.item(sticker)?.position, before, "an element beside the block stays")
        let items = editor.items
        for (i, a) in items.enumerated() {
            for b in items[(i + 1)...] {
                let apart = bottom(a) <= top(b) + 0.5 || bottom(b) <= top(a) + 0.5
                    || abs(a.position.x - b.position.x) >= (a.size.width + b.size.width) / 2
                XCTAssertTrue(apart, "nothing overlaps")
            }
        }
        XCTAssertEqual(top(editor.item(id)), 71, accuracy: 0.5, "the block keeps its top")
    }

    func testOneParagraphMakesNoNewBlock() {
        let (editor, id, _, _) = writingPage()
        XCTAssertEqual(editor.finishFullScreenWriting("  only this\n\n\n", height: height), [])
        XCTAssertEqual(texts(editor), ["only this"])
        XCTAssertEqual(editor.item(id)?.size.height, 58)
    }

    // MARK: Undo

    func testOneUndoTakesTheWholeSplitBack() {
        let (editor, id, photo, _) = writingPage()
        let page = editor.items
        let depth = editor.undoDepth
        editor.finishFullScreenWriting("first\n\nsecond\n\nthird", height: height)
        XCTAssertEqual(editor.undoDepth, depth, "the session's start is the step, as for typing")
        editor.undo()
        XCTAssertEqual(editor.items.count, 3)
        XCTAssertEqual(editor.item(photo)?.position, page.first { $0.id == photo }?.position)
        guard case .text(let block) = editor.item(id)?.content else { return XCTFail("the block stays") }
        XCTAssertEqual(block.text, "draft", "back to before the session")
    }

    func testAfterAStepInTheSessionDoneIsAStepOfItsOwn() {
        let (editor, id, _, _) = writingPage()
        editor.setTextAlignment(itemID: id, to: .leading)
        let depth = editor.undoDepth
        editor.finishFullScreenWriting("first\n\nsecond", height: height)
        XCTAssertEqual(editor.undoDepth, depth + 1)
        editor.undo()
        XCTAssertEqual(texts(editor), ["draft"], "one undo takes the split back, the alignment stays")
        guard case .text(let block) = editor.item(id)?.content else { return XCTFail("the block stays") }
        XCTAssertEqual(block.alignment, .leading)
    }

    func testANewBlockWrittenFullScreenGoesInOneUndo() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("", at: CGPoint(x: 195, y: 140))
        editor.startEditingText(id, recordingUndo: false)
        editor.finishFullScreenWriting("first\n\nsecond\n\nthird", height: height)
        XCTAssertEqual(editor.items.count, 3)
        editor.undo()
        XCTAssertTrue(editor.items.isEmpty)
        XCTAssertFalse(editor.canUndo, "no empty step left behind")
    }
}
