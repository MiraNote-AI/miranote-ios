import XCTest
@testable import MiraNoteKit

/// The Background tool's custom page color (screen 05 through the shared
/// custom color sheet): previewed live with no undo steps, then one step on
/// Apply, none on cancel.
@MainActor
final class PageColorPreviewTests: XCTestCase {
    func testAppliedPreviewIsOneUndoStepBackToTheOriginal() {
        let editor = CanvasViewModel(memory: Memory(backgroundFileName: "dusk.png", backgroundSummary: "a dusk sky"))
        let original = editor.pageLook
        editor.setPageColor("#D1E0F0", recordingUndo: false)
        editor.setPageColor("#8B5962", recordingUndo: false)
        XCTAssertFalse(editor.canUndo, "the drag previews without steps")

        editor.commitPagePreview(from: original)
        XCTAssertEqual(editor.memory.pageColorName, "#8B5962")
        XCTAssertEqual(editor.memory.backgroundFileName, "")

        editor.undo()
        XCTAssertFalse(editor.canUndo, "one step")
        XCTAssertEqual(editor.memory.pageColorName, "")
        XCTAssertEqual(editor.memory.backgroundFileName, "dusk.png", "the painting comes back")
        XCTAssertEqual(editor.memory.backgroundSummary, "a dusk sky")
    }

    func testAnUnchangedPreviewBurnsNoStep() {
        let editor = CanvasViewModel(memory: Memory())
        editor.setPageColor("#F6F4E8")
        let original = editor.pageLook
        let steps = editor.canUndo
        editor.setPageColor("#D1E0F0", recordingUndo: false)
        editor.setPageColor("#F6F4E8", recordingUndo: false)
        editor.commitPagePreview(from: original)
        editor.undo()
        XCTAssertEqual(editor.memory.pageColorName, "", "the only step is the first color")
        XCTAssertTrue(steps)
        XCTAssertFalse(editor.canUndo)
    }

    func testDiscardedPreviewRestoresThePageWithoutAStep() {
        let editor = CanvasViewModel(memory: Memory(backgroundFileName: "dusk.png", backgroundSummary: "a dusk sky"))
        let original = editor.pageLook
        editor.setPageColor("#D1E0F0", recordingUndo: false)
        editor.discardPagePreview(from: original)
        XCTAssertEqual(editor.pageLook, original)
        XCTAssertFalse(editor.canUndo)
    }
}
