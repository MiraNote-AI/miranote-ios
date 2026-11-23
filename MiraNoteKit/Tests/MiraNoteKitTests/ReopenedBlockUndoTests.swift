import XCTest
@testable import MiraNoteKit

/// A block reopened for writing records its undo point with the session's
/// first change (#236): every Undo after reopening a block changes
/// something, and each change is still one Undo.
@MainActor
final class ReopenedBlockUndoTests: XCTestCase {
    private func block(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> TextBlock? {
        guard case .text(let block) = editor.item(id)?.content else { return nil }
        return block
    }

    /// Undoes everything, failing at any Undo that leaves the page as it was.
    private func expectEveryUndoChangesSomething(_ editor: CanvasViewModel, _ label: String,
                                                 file: StaticString = #filePath, line: UInt = #line) {
        var undos = 0
        while editor.canUndo {
            let before = editor.items
            editor.undo()
            undos += 1
            XCTAssertNotEqual(editor.items, before, "\(label): undo \(undos) changed nothing", file: file, line: line)
        }
    }

    /// A reopened block whose first change is a style: three changes,
    /// three Undos, and the next takes back the step below the session.
    /// Before, the session's start and the size each recorded the same
    /// page, so a third Undo after the two real ones did nothing.
    func testAStyleFirstSessionHasNoUndoThatChangesNothing() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("lunch", at: CGPoint(x: 100, y: 100))
        editor.startEditingText(id)
        editor.setTextPointSize(itemID: id, to: 30)
        editor.setText(itemID: id, to: "lunch by the river")
        editor.endEditingText()

        editor.undo()
        XCTAssertEqual(block(editor, id)?.text, "lunch", "the words")
        XCTAssertEqual(block(editor, id)?.pointSize, 30)
        editor.undo()
        XCTAssertEqual(block(editor, id)?.pointSize, 17, "the size")
        editor.undo()
        XCTAssertNil(editor.item(id), "then the block's adding, nothing in between")
        XCTAssertFalse(editor.canUndo)
    }

    /// Reopened and left with no change, or Undo right after reopening:
    /// the Undo takes back the step below, and writing goes on while the
    /// block is still there.
    func testAnUnchangedVisitLeavesNoUndoStep() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("lunch", at: CGPoint(x: 100, y: 100))
        let photo = editor.addImages([ImageRef(displayName: "p")], around: CGPoint(x: 100, y: 400))[0]
        let depth = editor.undoDepth
        editor.startEditingText(id)
        editor.endEditingText()
        XCTAssertEqual(editor.undoDepth, depth, "looking at a block records nothing")

        editor.startEditingText(id)
        editor.undo()
        XCTAssertNil(editor.item(photo), "the Undo took the photo back")
        XCTAssertEqual(editor.editingTextItemID, id, "still writing")
        expectEveryUndoChangesSomething(editor, "after a visit")
    }

    /// Every way a session's first change can be recorded leaves no Undo
    /// that restores the same page: a font, a highlight, a color from the
    /// sheet, a rewrite kept from the AI row, words typed.
    func testEveryFirstChangeOfAReopenedBlockUndoesOnce() throws {
        let firstChanges: [(String, (CanvasViewModel, CanvasItem.ID) throws -> Void)] = [
            ("font", { $0.setTextFont(itemID: $1, to: "Futura") }),
            ("highlight", { $0.setTextBackground(itemID: $1, to: "#24382D") }),
            ("sheet color", { editor, id in
                let original = try XCTUnwrap(editor.item(id))
                editor.setTextColorName(itemID: id, to: "#E5AC95", recordingUndo: false)
                editor.commitPreview(of: original)
            }),
            ("rewrite", { editor, id in
                let original = try XCTUnwrap(editor.item(id))
                editor.setText(itemID: id, to: "Lunch.")
                editor.setText(itemID: id, to: "Lunch by the river, warm.")
                editor.commitPreview(of: original)
            }),
            ("typing", { $0.setText(itemID: $1, to: "lunch with Sam") })
        ]
        for (label, change) in firstChanges {
            let editor = CanvasViewModel(memory: Memory())
            let id = editor.addText("lunch", at: CGPoint(x: 100, y: 100))
            editor.startEditingText(id)
            try change(editor, id)
            editor.setTextAlignment(itemID: id, to: .center)
            editor.endEditingText()
            XCTAssertEqual(editor.undoDepth, 3, "\(label): the adding, the change, the alignment")
            expectEveryUndoChangesSomething(editor, label)
        }
    }

    /// A block with a photo below it, reopened: a version shown as the AI
    /// row does (its words, then the box fitted to them, pushing the photo).
    private func showVersion(_ editor: CanvasViewModel, _ id: CanvasItem.ID, _ text: String, height: CGFloat) {
        editor.setText(itemID: id, to: text)
        editor.autosizeTextHeight(itemID: id, to: height)
    }

    private func blockAbovePhoto(_ editor: CanvasViewModel) -> (CanvasItem.ID, CanvasItem.ID) {
        let id = editor.addText("lunch", at: CGPoint(x: 120, y: 100.3))
        editor.autosizeTextHeight(itemID: id, to: 36.3)
        let photo = editor.addImages([ImageRef(displayName: "p")], around: CGPoint(x: 120, y: 300.3))[0]
        return (id, photo)
    }

    /// A size, then a rewrite kept from the AI row: two changes, two Undos.
    /// Before, the rewrite's first words recorded the page before it and
    /// keeping it recorded the same page again, so one Undo did nothing.
    func testASizeThenARewriteUndoOnceEach() throws {
        for sized in [false, true] {
            let label = sized ? "after a size" : "rewrite only"
            let editor = CanvasViewModel(memory: Memory())
            let (id, photo) = blockAbovePhoto(editor)
            let photoAt = try XCTUnwrap(editor.item(photo)).position
            let depth = editor.undoDepth
            editor.startEditingText(id)
            if sized { editor.setTextPointSize(itemID: id, to: 30) }
            let original = try XCTUnwrap(editor.item(id))
            showVersion(editor, id, "Lunch by the river, warm.", height: 100.1)
            XCTAssertGreaterThan(try XCTUnwrap(editor.item(photo)).position.y, photoAt.y, "\(label): pushed")
            editor.commitPreview(of: original)
            editor.endEditingText()
            XCTAssertEqual(editor.undoDepth, depth + (sized ? 2 : 1), "\(label): one step per change")

            editor.undo()
            XCTAssertEqual(block(editor, id)?.text, "lunch", "\(label): the rewrite")
            XCTAssertEqual(block(editor, id)?.pointSize, sized ? 30 : 17)
            XCTAssertEqual(try XCTUnwrap(editor.item(photo)).position.y, photoAt.y, accuracy: 0.5)
            if sized {
                editor.undo()
                XCTAssertEqual(block(editor, id)?.pointSize, 17, "then the size")
            }
            editor.undo()
            XCTAssertNil(editor.item(photo), "\(label): then the photo's adding, nothing in between")
        }
    }

    /// A version shown, then Original picked again: the page is as it was,
    /// so the AI row leaves no step -- on its own or after a size.
    func testAVersionTakenBackToOriginalLeavesNoStep() throws {
        for sized in [false, true] {
            let label = sized ? "after a size" : "rewrite only"
            let editor = CanvasViewModel(memory: Memory())
            let (id, photo) = blockAbovePhoto(editor)
            let depth = editor.undoDepth
            editor.startEditingText(id)
            if sized { editor.setTextPointSize(itemID: id, to: 30) }
            let original = try XCTUnwrap(editor.item(id))
            showVersion(editor, id, "Lunch by the river, warm.", height: 100.1)
            showVersion(editor, id, "lunch", height: original.size.height)
            editor.commitPreview(of: original)
            XCTAssertEqual(editor.undoDepth, depth + (sized ? 1 : 0), "\(label): only the size")

            editor.setText(itemID: id, to: "lunch with Sam")
            editor.endEditingText()
            editor.undo()
            XCTAssertEqual(block(editor, id)?.text, "lunch", "\(label): the words typed after, alone")
            XCTAssertEqual(block(editor, id)?.pointSize, sized ? 30 : 17, "\(label): the size stays")
            if sized {
                editor.undo()
                XCTAssertEqual(block(editor, id)?.pointSize, 17, "then the size")
            }
            editor.undo()
            XCTAssertNil(editor.item(photo), "\(label): then the photo's adding, nothing in between")
        }
    }

    /// Cancel after a version went back to Original: the session's words
    /// typed since go, the block is as it was, and no step is left over.
    func testCancelAfterAVersionTakenBack() throws {
        let editor = CanvasViewModel(memory: Memory())
        let (id, photo) = blockAbovePhoto(editor)
        let depth = editor.undoDepth
        editor.startEditingText(id)
        let original = try XCTUnwrap(editor.item(id))
        showVersion(editor, id, "Lunch by the river, warm.", height: 100.1)
        showVersion(editor, id, "lunch", height: original.size.height)
        editor.commitPreview(of: original)
        editor.setText(itemID: id, to: "lunch with Sam")
        editor.cancelEditingText()
        XCTAssertEqual(block(editor, id)?.text, "lunch")
        XCTAssertEqual(editor.undoDepth, depth, "nothing of the session is left to undo")
        editor.undo()
        XCTAssertNil(editor.item(photo), "the Undo takes back the step below")
    }

    /// A page tap ends the session before the AI row's version is kept
    /// (the scene commits it once the session has ended): still one step
    /// for a version kept, none for one taken back to Original.
    func testAPageTapKeepsTheVersionAsOneStep() throws {
        for takenBack in [false, true] {
            let label = takenBack ? "taken back" : "kept"
            let editor = CanvasViewModel(memory: Memory())
            let (id, _) = blockAbovePhoto(editor)
            let depth = editor.undoDepth
            editor.startEditingText(id)
            let original = try XCTUnwrap(editor.item(id))
            showVersion(editor, id, "Lunch by the river, warm.", height: 100.1)
            if takenBack { showVersion(editor, id, "lunch", height: original.size.height) }
            editor.endEditingText()
            editor.select(nil)
            editor.commitPreview(of: original)
            XCTAssertEqual(editor.undoDepth, depth + (takenBack ? 0 : 1), label)
        }
    }
}
