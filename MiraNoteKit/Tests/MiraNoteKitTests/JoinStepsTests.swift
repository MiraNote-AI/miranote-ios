import XCTest
@testable import MiraNoteKit

/// The Image tool's Add (#205 G8): the photos one Add places are one undo
/// step, and one redo puts them all back.
@MainActor
final class JoinStepsTests: XCTestCase {
    private func photos(_ editor: CanvasViewModel, _ count: Int) -> [CanvasItem.ID] {
        (0..<count).map { index in
            editor.addImages([ImageRef(displayName: "p\(index)", fileName: "p\(index).jpg")],
                             around: CGPoint(x: 150, y: 150))[0]
        }
    }

    func testJoinedPhotosUndoAndRedoTogether() {
        let editor = CanvasViewModel(memory: Memory())
        let kept = editor.addText("hello", at: CGPoint(x: 100, y: 60), pointSize: 17,
                                  size: CGSize(width: 200, height: 48))
        _ = photos(editor, 3)
        editor.joinLastSteps(3)
        XCTAssertEqual(editor.undoDepth, 2, "the text's step and one for the batch")

        editor.undo()
        XCTAssertEqual(editor.items.map(\.id), [kept], "one undo takes every photo back")
        editor.redo()
        XCTAssertEqual(editor.items.count, 4, "one redo returns them all")
    }

    /// A slow import can land while a block is written: the joined photos
    /// count as one of the session's steps, so its Cancel still takes back
    /// the words and keeps the photos, one Undo for the batch.
    func testJoiningWhileWritingKeepsTheSessionsCancel() {
        let editor = CanvasViewModel(memory: Memory())
        let block = editor.addText("hello", at: CGPoint(x: 100, y: 60), pointSize: 17,
                                   size: CGSize(width: 200, height: 48))
        editor.startEditingText(block)
        editor.setText(itemID: block, to: "hello world")
        let placed = photos(editor, 3)
        editor.joinLastSteps(3)

        editor.cancelEditingText()
        XCTAssertEqual(text(of: block, in: editor), "hello", "Cancel takes the words back")
        XCTAssertEqual(editor.items.count, 4, "the photos stay")
        editor.undo()
        XCTAssertEqual(Set(editor.items.map(\.id)).intersection(placed), [], "one undo takes the batch back")
        XCTAssertEqual(text(of: block, in: editor), "hello")
    }

    private func text(of id: CanvasItem.ID, in editor: CanvasViewModel) -> String? {
        guard case .text(let block) = editor.item(id)?.content else { return nil }
        return block.text
    }

    func testJoiningOneOrMoreThanRecordedChangesNothing() {
        let editor = CanvasViewModel(memory: Memory())
        _ = photos(editor, 2)
        editor.joinLastSteps(1)
        XCTAssertEqual(editor.undoDepth, 2)
        editor.joinLastSteps(3)
        XCTAssertEqual(editor.undoDepth, 2)
    }
}
