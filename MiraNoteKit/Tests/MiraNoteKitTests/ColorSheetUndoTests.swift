import XCTest
@testable import MiraNoteKit

/// The custom color sheet commits through `commitPreview`, as the AI row
/// does (#252): on a reopened block, its Apply is one undo step of its
/// own, and an Apply that leaves the page as it is leaves no step that
/// changes nothing.
@MainActor
final class ColorSheetUndoTests: XCTestCase {
    private func block(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> TextBlock? {
        guard case .text(let block) = editor.item(id)?.content else { return nil }
        return block
    }

    private func blockAbovePhoto(_ editor: CanvasViewModel) -> (CanvasItem.ID, CanvasItem.ID) {
        let id = editor.addText("lunch", at: CGPoint(x: 120, y: 100.3))
        editor.autosizeTextHeight(itemID: id, to: 36.3)
        let photo = editor.addImages([ImageRef(displayName: "p")], around: CGPoint(x: 120, y: 300.3))[0]
        return (id, photo)
    }

    /// The sheet's Apply: `color` previewed live, then kept.
    private func applySheet(_ editor: CanvasViewModel, _ id: CanvasItem.ID, _ color: String) throws {
        let original = try XCTUnwrap(editor.item(id))
        editor.setTextColorName(itemID: id, to: "#112233", recordingUndo: false)
        editor.setTextColorName(itemID: id, to: color, recordingUndo: false)
        editor.commitPreview(of: original)
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

    /// A size (re-measured, pushing the photo, as the app does), then a
    /// color from the sheet: two changes, two Undos.
    func testAColorAfterASizeIsAStepOfItsOwn() throws {
        let editor = CanvasViewModel(memory: Memory())
        let (id, photo) = blockAbovePhoto(editor)
        let photoAt = try XCTUnwrap(editor.item(photo)).position
        let depth = editor.undoDepth
        editor.startEditingText(id)
        editor.setTextPointSize(itemID: id, to: 30)
        editor.autosizeTextHeight(itemID: id, to: 96.2)
        XCTAssertGreaterThan(try XCTUnwrap(editor.item(photo)).position.y, photoAt.y, "the size pushed the photo")
        try applySheet(editor, id, "#E5AC95")
        editor.endEditingText()
        XCTAssertEqual(editor.undoDepth, depth + 2, "the size and the color")

        editor.undo()
        XCTAssertEqual(block(editor, id)?.colorName, "ink", "the color")
        XCTAssertEqual(block(editor, id)?.pointSize, 30)
        editor.undo()
        XCTAssertEqual(block(editor, id)?.pointSize, 17, "then the size")
        XCTAssertEqual(try XCTUnwrap(editor.item(photo)).position.y, photoAt.y, accuracy: 0.5)
        editor.undo()
        XCTAssertNil(editor.item(photo), "then the photo's adding, nothing in between")
    }

    /// Words typed and typed away again, then the sheet. Its color is one
    /// Undo; an Apply of the block's own color leaves none -- the words'
    /// step restores the page as it is, so it goes too.
    func testTheSheetAfterWordsTypedAwayLeavesNoUndoThatChangesNothing() throws {
        for recolored in [true, false] {
            let label = recolored ? "a new color" : "its own color"
            let editor = CanvasViewModel(memory: Memory())
            let (id, _) = blockAbovePhoto(editor)
            let depth = editor.undoDepth
            editor.startEditingText(id)
            editor.setText(itemID: id, to: "lunch!")
            editor.setText(itemID: id, to: "lunch")
            try applySheet(editor, id, recolored ? "#E5AC95" : "ink")
            editor.endEditingText()
            XCTAssertEqual(editor.undoDepth, depth + (recolored ? 1 : 0), label)
            expectEveryUndoChangesSomething(editor, label)
        }
    }
}
