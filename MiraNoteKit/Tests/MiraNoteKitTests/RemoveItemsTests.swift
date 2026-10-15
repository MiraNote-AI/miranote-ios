import XCTest
@testable import MiraNoteKit

/// The Image tool's Cancel (handoff screens 24-25): the photos it placed
/// come off the page together, and one undo puts them all back.
@MainActor
final class RemoveItemsTests: XCTestCase {
    private func photos(_ editor: CanvasViewModel, _ count: Int) -> [CanvasItem.ID] {
        (0..<count).map { index in
            editor.addImages([ImageRef(displayName: "p\(index)", fileName: "p\(index).jpg")],
                             around: CGPoint(x: 150, y: 150))[0]
        }
    }

    func testRemovesSeveralAsOneUndoStep() {
        let editor = CanvasViewModel(memory: Memory())
        let kept = editor.addText("hello", at: CGPoint(x: 100, y: 60), pointSize: 17,
                                  size: CGSize(width: 200, height: 48))
        let placed = photos(editor, 3)
        editor.select(placed[1])

        editor.remove(itemIDs: placed)
        XCTAssertEqual(editor.items.map(\.id), [kept])
        XCTAssertNil(editor.selectedItemID, "a removed selection clears")

        editor.undo()
        XCTAssertEqual(editor.items.count, 4, "one undo returns every photo")
    }

    func testIdsAlreadyGoneRecordNothing() {
        let editor = CanvasViewModel(memory: Memory())
        let placed = photos(editor, 1)
        editor.delete(itemID: placed[0])
        let count = editor.changeCount

        editor.remove(itemIDs: placed)
        XCTAssertEqual(editor.changeCount, count)
    }
}
