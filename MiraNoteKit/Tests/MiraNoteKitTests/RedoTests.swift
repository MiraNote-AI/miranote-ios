import XCTest
@testable import MiraNoteKit

/// Redo (handoff screens 32-34): the floating Redo puts back what Undo
/// took, and any new change ends the redo trail.
@MainActor
final class RedoTests: XCTestCase {
    private func filter(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> String? {
        guard case .image(let ref) = editor.item(id)?.content else { return nil }
        return ref.filterName
    }

    private func photo() -> (CanvasViewModel, CanvasItem.ID) {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addImages([ImageRef(displayName: "roses", fileName: "a.jpg")],
                                  around: CGPoint(x: 150, y: 150))[0]
        return (editor, id)
    }

    // The text editor's header Cancel (screens 10-20) takes the session
    // back even after an undo and a redo inside it, and nothing of the
    // session comes back by redo.
    func testCancelledTextSessionLeavesNothingToRedo() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("kept words", at: CGPoint(x: 100, y: 100))
        editor.startEditingText(id)
        editor.setTextColorName(itemID: id, to: "#FFFFFF")
        editor.setTextAlignment(itemID: id, to: .center)
        editor.undo()
        editor.redo()
        editor.undo()
        XCTAssertTrue(editor.canRedo)

        editor.cancelEditingText()
        guard case .text(let block) = editor.item(id)?.content else { return XCTFail("the block stays") }
        XCTAssertEqual(block.colorName, "ink")
        XCTAssertEqual(block.alignment, .leading)
        XCTAssertFalse(editor.canRedo, "a cancelled session is not redoable")
        editor.undo()
        XCTAssertNil(editor.item(id), "the next undo is the step before the session")
    }

    func testNothingToRedoUntilSomethingIsUndone() {
        let (editor, id) = photo()
        editor.setImageFilter(itemID: id, to: "bw")
        XCTAssertFalse(editor.canRedo)

        let count = editor.changeCount
        editor.redo()
        XCTAssertEqual(editor.changeCount, count, "an empty redo changes nothing")
        XCTAssertEqual(filter(editor, id), "bw")
    }

    func testRedoReappliesUndoneStepsInOrder() {
        let (editor, id) = photo()
        editor.setImageFilter(itemID: id, to: "bw")
        editor.setImageFrame(itemID: id, to: "polaroid")

        editor.undo()
        editor.undo()
        XCTAssertEqual(filter(editor, id), "")
        XCTAssertTrue(editor.canRedo)

        editor.redo()
        XCTAssertEqual(filter(editor, id), "bw")
        guard case .image(let afterOne) = editor.item(id)?.content else { return XCTFail("photo gone") }
        XCTAssertEqual(afterOne.frameName, "", "one redo is one step")

        editor.redo()
        guard case .image(let afterTwo) = editor.item(id)?.content else { return XCTFail("photo gone") }
        XCTAssertEqual(afterTwo.frameName, "polaroid")
        XCTAssertFalse(editor.canRedo)
    }

    func testRedoIsItselfUndoable() {
        let (editor, id) = photo()
        editor.setImageFilter(itemID: id, to: "bw")
        editor.undo()
        editor.redo()

        editor.undo()
        XCTAssertEqual(filter(editor, id), "")
        XCTAssertTrue(editor.canRedo)
    }

    func testANewChangeDropsTheRedoTrail() {
        let (editor, id) = photo()
        editor.setImageFilter(itemID: id, to: "bw")
        editor.undo()

        editor.setImageFilter(itemID: id, to: "warm")
        XCTAssertFalse(editor.canRedo)
        editor.redo()
        XCTAssertEqual(filter(editor, id), "warm", "redo must not rewrite the newer edit")
    }

    func testRedoBumpsTheChangeCount() {
        let (editor, id) = photo()
        editor.setImageFilter(itemID: id, to: "bw")
        editor.undo()
        let count = editor.changeCount
        editor.redo()
        XCTAssertGreaterThan(editor.changeCount, count, "receipts see a redo as a change")
    }

    func testRedoBringsBackARemovedElement() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addImages([ImageRef(displayName: "roses", fileName: "a.jpg")],
                                  around: CGPoint(x: 150, y: 150))[0]
        editor.undo()
        XCTAssertNil(editor.item(id))
        editor.redo()
        XCTAssertNotNil(editor.item(id))
    }

    func testDiscardingAnAbandonedBlockDropsTheRedoTrail() {
        let (editor, id) = photo()
        editor.setImageFilter(itemID: id, to: "bw")
        editor.undo()
        let text = editor.addText("", at: CGPoint(x: 100, y: 100), pointSize: 17,
                                  size: CGSize(width: 200, height: 48))
        editor.discardAbandonedText(itemID: text)
        XCTAssertFalse(editor.canRedo)
    }
}
