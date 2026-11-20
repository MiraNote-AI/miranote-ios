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

    func testJoiningOneOrMoreThanRecordedChangesNothing() {
        let editor = CanvasViewModel(memory: Memory())
        _ = photos(editor, 2)
        editor.joinLastSteps(1)
        XCTAssertEqual(editor.undoDepth, 2)
        editor.joinLastSteps(3)
        XCTAssertEqual(editor.undoDepth, 2)
    }
}
