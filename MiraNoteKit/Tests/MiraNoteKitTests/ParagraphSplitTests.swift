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

    func testBlankLinesSplitAndSingleBreaksStayInside() {
        XCTAssertEqual(ParagraphSplit.paragraphs(of: "one\ntwo\n\nthree\n\n \n\nfour"),
                       ["one\ntwo", "three", "four"])
    }

    func testTrailingSpacesAreTrimmedAndBlankLinesDropped() {
        XCTAssertEqual(ParagraphSplit.paragraphs(of: "\n\n  one  \n \t \n\n   \n two\n\n"), ["  one", " two"])
        XCTAssertEqual(ParagraphSplit.paragraphs(of: " \n\n \n"), [])
        XCTAssertEqual(ParagraphSplit.paragraphs(of: ""), [])
    }

    func testWindowsLineBreaksCountAsOne() {
        XCTAssertEqual(ParagraphSplit.paragraphs(of: "one\r\ntwo\r\n\r\nthree"), ["one\ntwo", "three"])
    }

    /// Chinese prose opens each paragraph with two ideographic spaces.
    func testAChineseIndentIsKept() {
        let indent = "\u{3000}\u{3000}"
        let first = indent + "\u{4ECA}\u{5929}\u{4E0B}\u{96E8}\u{3002}"
        let second = indent + "\u{660E}\u{5929}\u{653E}\u{6674}\u{3002}"
        XCTAssertEqual(ParagraphSplit.paragraphs(of: first + "\n\n" + second), [first, second])
    }

    func testAListKeepsTheIndentOfItsFirstItem() {
        XCTAssertEqual(ParagraphSplit.paragraphs(of: "Shopping\n\n  - milk\n  - eggs"),
                       ["Shopping", "  - milk\n  - eggs"])
    }

    // MARK: Placing

    private struct Page {
        let editor: CanvasViewModel
        let block: CanvasItem.ID
        let photo: CanvasItem.ID
        let sticker: CanvasItem.ID
    }

    /// A styled block at the top, a photo 40 below it, and a sticker
    /// beside the block; `words` were just written into the block and the
    /// writing ended.
    private func writtenPage(_ words: String) -> Page {
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
        return Page(editor: editor, block: block.id, photo: photo.id, sticker: sticker.id)
    }

    func testEachParagraphBecomesABlockInTheBlocksStyle() {
        let page = writtenPage("first\n\nsecond\n \n\nthird")
        let (editor, id) = (page.editor, page.block)
        let new = editor.splitParagraphs(of: id, height: height)

        XCTAssertEqual(new.count, 2)
        XCTAssertEqual(texts(editor), ["first", "second", "third"])
        guard case .text(let kept) = editor.item(id)?.content else { return XCTFail("the block stays") }
        let stack = [id] + new
        for (upperID, lowerID) in zip(stack, stack.dropFirst()) {
            let upper = editor.item(upperID), lower = editor.item(lowerID)
            XCTAssertEqual(top(lower) - bottom(upper), ParagraphSplit.gap, accuracy: 0.5,
                           "directly below, a gap apart")
            XCTAssertEqual(lower?.position.x, upper?.position.x)
            XCTAssertEqual(lower?.size.width, upper?.size.width)
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
        let page = writtenPage("first\n\nsecond\n\nthird")
        let (editor, id, photo, sticker) = (page.editor, page.block, page.photo, page.sticker)
        let before = editor.item(sticker)?.position
        let new = editor.splitParagraphs(of: id, height: height)
        XCTAssertEqual(top(editor.item(photo)) - bottom(editor.item(new.last!)), 40, accuracy: 0.5,
                       "the photo keeps its gap under the last block")
        XCTAssertEqual(editor.item(sticker)?.position, before, "an element beside the block stays")
        let items = editor.items
        for (index, one) in items.enumerated() {
            for other in items[(index + 1)...] {
                let apart = bottom(one) <= top(other) + 0.5 || bottom(other) <= top(one) + 0.5
                    || abs(one.position.x - other.position.x) >= (one.size.width + other.size.width) / 2
                XCTAssertTrue(apart, "nothing overlaps")
            }
        }
        XCTAssertEqual(top(editor.item(id)), 71, accuracy: 0.5, "the block keeps its top")
    }

    func testOneParagraphIsLeftAlone() {
        for words in ["  only this  ", "a poem\nkeeps its lines", "  one paragraph\n\n\n"] {
            let page = writtenPage(words)
            let (editor, id) = (page.editor, page.block)
            let depth = editor.undoDepth
            XCTAssertEqual(editor.splitParagraphs(of: id, height: height), [])
            XCTAssertEqual(texts(editor), [words], "as written")
            XCTAssertEqual(editor.undoDepth, depth, "no step")
        }
    }

    func testABlankLineMakesTwoBlocksASingleBreakStaysInside() {
        let page = writtenPage("a\nb\n\nc")
        let (editor, id) = (page.editor, page.block)
        XCTAssertEqual(editor.splitParagraphs(of: id, height: height).count, 1)
        XCTAssertEqual(texts(editor), ["a\nb", "c"])
    }

    // MARK: Undo

    func testOneUndoGivesBackTheSingleBlock() {
        let written = writtenPage("first\n\nsecond\n\nthird")
        let (editor, id, photo) = (written.editor, written.block, written.photo)
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

    // MARK: Only a session that added a paragraph break splits

    /// `words` on the page as one block, as a joined split, an old page's
    /// body or a Mira reply leave it; opened and ended with `typed` added.
    private func reopened(_ words: String, typing typed: String = "") -> (CanvasViewModel, CanvasItem.ID) {
        let block = CanvasItem(content: .text(TextBlock(text: words)), position: CGPoint(x: 150, y: 200),
                               size: CGSize(width: 230, height: 120))
        let editor = CanvasViewModel(memory: Memory(items: [block]))
        editor.startEditingText(block.id)
        if !typed.isEmpty { editor.setText(itemID: block.id, to: words + typed) }
        editor.endEditingText()
        return (editor, block.id)
    }

    func testABlockOpenedAndLeftAsItWasStaysWhole() {
        let (editor, id) = reopened("alpha\n\nbeta")
        XCTAssertEqual(editor.splitParagraphs(of: id, height: height), [])
        XCTAssertEqual(texts(editor), ["alpha\n\nbeta"])
    }

    func testABlockGivenAWordButNoNewParagraphStaysWhole() {
        let (editor, id) = reopened("alpha\n\nbeta", typing: " and gamma")
        XCTAssertEqual(editor.splitParagraphs(of: id, height: height), [])
        XCTAssertEqual(texts(editor), ["alpha\n\nbeta and gamma"])
    }

    func testABlockGivenANewParagraphSplitsWhole() {
        let (editor, id) = reopened("alpha\n\nbeta", typing: "\n\ngamma")
        XCTAssertEqual(editor.splitParagraphs(of: id, height: height).count, 2)
        XCTAssertEqual(texts(editor), ["alpha", "beta", "gamma"])
    }

    func testAJoinedSplitIsNotSplitAgainByDoneWithNoChange() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("", at: CGPoint(x: 195, y: 140))
        editor.startEditingText(id, recordingUndo: false)
        editor.setText(itemID: id, to: "alpha\n\nbeta")
        editor.endEditingText()
        XCTAssertEqual(editor.splitParagraphs(of: id, height: height).count, 1)
        editor.undo()
        XCTAssertEqual(texts(editor), ["alpha\n\nbeta"], "joined back")

        editor.startEditingText(id)
        editor.endEditingText()
        XCTAssertEqual(editor.splitParagraphs(of: id, height: height), [])
        XCTAssertEqual(texts(editor), ["alpha\n\nbeta"], "still one block")
    }

    func testOnlyTheSessionThatJustEndedSplits() {
        let (editor, id) = reopened("alpha", typing: "\n\nbeta")
        XCTAssertEqual(editor.splitParagraphs(of: id, height: height).count, 1)
        XCTAssertEqual(editor.splitParagraphs(of: id, height: height), [], "once")
    }

    // MARK: A rewrite open when the writing ends

    /// The app keeps an open rewrite preview (its own step) before it
    /// splits: an Expand whose first paragraph differs from the words typed
    /// gives two steps back to those words, and no step records a page
    /// that never was (the typed words with the rewrite's later paragraphs).
    func testAnOpenExpandIsKeptBeforeTheSplit() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("", at: CGPoint(x: 195, y: 140))
        editor.startEditingText(id, recordingUndo: false)
        editor.setText(itemID: id, to: "noodle shop")
        guard let original = editor.item(id) else { return XCTFail("the block") }
        let expanded = "A noodle shop on the corner.\n\nIt opens at six."
        editor.setText(itemID: id, to: expanded)
        editor.endEditingText()
        editor.commitPreview(of: original)
        XCTAssertEqual(editor.splitParagraphs(of: id, height: height).count, 1, "the Expand added a paragraph")
        XCTAssertEqual(texts(editor), ["A noodle shop on the corner.", "It opens at six."])

        editor.undo()
        XCTAssertEqual(texts(editor), [expanded], "the expanded block, whole")
        editor.undo()
        XCTAssertEqual(texts(editor), ["noodle shop"], "the words as typed")
    }

    // MARK: Placing a written block that grew

    /// A block grown to 200 while it was written, a sticker beside its
    /// lower half and a photo under it, in its column.
    func testOnlyWhatIsUnderTheWrittenBlockInItsColumnsMoves() {
        let block = CanvasItem(content: .text(TextBlock(text: "draft")), position: CGPoint(x: 150, y: 200),
                               size: CGSize(width: 230, height: 200), rotation: 6)
        let sticker = CanvasItem(content: .sticker(GeneratedSticker(prompt: "sun", symbolName: "sun.max")),
                                 position: CGPoint(x: 330, y: 220), size: CGSize(width: 50, height: 50), zIndex: 1)
        let photo = CanvasItem(content: .image(ImageRef(displayName: "photo")),
                               position: CGPoint(x: 160, y: 300 + 40 + 80), size: CGSize(width: 200, height: 160),
                               zIndex: 2)
        let editor = CanvasViewModel(memory: Memory(items: [block, sticker, photo]))
        editor.startEditingText(block.id)
        editor.setText(itemID: block.id, to: "first\n\nsecond")
        editor.endEditingText()
        let new = editor.splitParagraphs(of: block.id, height: height)

        XCTAssertEqual(editor.item(sticker.id)?.position, sticker.position, "beside the block, it stays")
        XCTAssertGreaterThan(top(editor.item(photo.id)), bottom(editor.item(new[0])), "under the stack")
        XCTAssertEqual(editor.item(new[0])?.rotation, 6, "the new block keeps the tilt")
    }

    /// #188 review: a wide photo under the block and a sticker under the
    /// photo but beside the block. Writing grew the block and pushed both;
    /// the split moves the sticker with the photo, not back onto it.
    func testWhatIsUnderAMovingElementMovesWithItInAChain() {
        let block = CanvasItem(content: .text(TextBlock(text: "draft")), position: CGPoint(x: 150, y: 129),
                               size: CGSize(width: 230, height: 58))
        let photo = CanvasItem(content: .image(ImageRef(displayName: "photo")),
                               position: CGPoint(x: 200, y: 268), size: CGSize(width: 360, height: 140), zIndex: 1)
        let sticker = CanvasItem(content: .sticker(GeneratedSticker(prompt: "sun", symbolName: "sun.max")),
                                 position: CGPoint(x: 340, y: 383), size: CGSize(width: 50, height: 50), zIndex: 2)
        let editor = CanvasViewModel(memory: Memory(items: [block, photo, sticker]))
        editor.startEditingText(block.id)
        editor.setText(itemID: block.id, to: "first line\n\nsecond line\n\nthird line")
        editor.fitTextHeights { item in
            guard case .text(let text) = item.content else { return nil }
            return self.height(text, item.size.width)
        }
        XCTAssertEqual(top(editor.item(sticker.id)) - bottom(editor.item(photo.id)), 20, accuracy: 0.5,
                       "the growth pushed both")
        editor.endEditingText()
        let new = editor.splitParagraphs(of: block.id, height: height)

        XCTAssertEqual(new.count, 2)
        XCTAssertEqual(top(editor.item(photo.id)) - bottom(editor.item(new.last!)), 40, accuracy: 0.5,
                       "the photo keeps its gap under the stack")
        XCTAssertEqual(top(editor.item(sticker.id)) - bottom(editor.item(photo.id)), 20, accuracy: 0.5,
                       "the sticker keeps its gap under the photo")
    }
}
