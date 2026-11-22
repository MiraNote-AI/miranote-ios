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
}
