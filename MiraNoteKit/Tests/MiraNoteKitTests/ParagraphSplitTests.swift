import XCTest
@testable import MiraNoteKit

/// #184: when writing ends, the words split on blank lines into one block
/// per paragraph, stacked under the block that was written.
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

    /// The app's rule.
    func testBlankLineRuleKeepsSingleBreaksInside() {
        XCTAssertEqual(ParagraphSplit.paragraphs(of: "one\ntwo\n\nthree\n\n \n\nfour", everyLine: false),
                       ["one\ntwo", "three", "four"])
    }

    // MARK: Placing

    /// A styled block at the top, a photo 40 below it, and a sticker
    /// beside the block; `words` were just written into the block and the
    /// writing ended.
    private func writtenPage(
        _ words: String
    ) -> (CanvasViewModel, block: CanvasItem.ID, photo: CanvasItem.ID, sticker: CanvasItem.ID) {
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
        editor.setText(itemID: block.id, to: words)
        editor.endEditingText()
        return (editor, block.id, photo.id, sticker.id)
    }

    func testEachParagraphBecomesABlockInTheBlocksStyle() {
        let (editor, id, _, _) = writtenPage("first\n\nsecond\n \n\nthird")
        let new = editor.splitParagraphs(of: id, height: height)

        XCTAssertEqual(new.count, 2)
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
        let (editor, id, photo, sticker) = writtenPage("first\n\nsecond\n\nthird")
        let before = editor.item(sticker)?.position
        let new = editor.splitParagraphs(of: id, height: height)
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

    func testOneParagraphIsLeftAlone() {
        for words in ["  only this  ", "a poem\nkeeps its lines", "  one paragraph\n\n\n"] {
            let (editor, id, _, _) = writtenPage(words)
            let depth = editor.undoDepth
            XCTAssertEqual(editor.splitParagraphs(of: id, height: height), [])
            XCTAssertEqual(texts(editor), [words], "as written")
            XCTAssertEqual(editor.undoDepth, depth, "no step")
        }
    }

    func testABlankLineMakesTwoBlocksASingleBreakStaysInside() {
        let (editor, id, _, _) = writtenPage("a\nb\n\nc")
        XCTAssertEqual(editor.splitParagraphs(of: id, height: height).count, 1)
        XCTAssertEqual(texts(editor), ["a\nb", "c"])
    }

    // MARK: Undo

    func testOneUndoGivesBackTheSingleBlock() {
        let (editor, id, photo, _) = writtenPage("first\n\nsecond\n\nthird")
        let page = editor.items
        let depth = editor.undoDepth
        editor.splitParagraphs(of: id, height: height)
        XCTAssertEqual(editor.undoDepth, depth + 1, "the split is one step of its own")
        editor.undo()
        XCTAssertEqual(editor.items, page, "the single block, the photo where it was")
        XCTAssertEqual(editor.item(photo)?.position, page.first { $0.id == photo }?.position)
        editor.undo()
        guard case .text(let block) = editor.item(id)?.content else { return XCTFail("the block stays") }
        XCTAssertEqual(block.text, "draft", "the next undo goes back to before the writing")
    }

    func testANewBlockSplitsThenUndoesToOneBlock() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("", at: CGPoint(x: 195, y: 140))
        editor.startEditingText(id, recordingUndo: false)
        editor.setText(itemID: id, to: "first\n\nsecond\n\nthird")
        editor.endEditingText()
        editor.splitParagraphs(of: id, height: height)
        XCTAssertEqual(editor.items.count, 3)
        editor.undo()
        XCTAssertEqual(texts(editor), ["first\n\nsecond\n\nthird"])
        editor.undo()
        XCTAssertTrue(editor.items.isEmpty)
        XCTAssertFalse(editor.canUndo, "no empty step left behind")
    }
}
