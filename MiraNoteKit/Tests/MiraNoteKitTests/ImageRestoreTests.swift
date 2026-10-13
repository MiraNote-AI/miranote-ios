import XCTest
@testable import MiraNoteKit

/// Photo edit revert (handoff screens 27-28): the panel can put a photo
/// back the way it was when editing began, as one undo step.
@MainActor
final class ImageRestoreTests: XCTestCase {
    private func ref(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> ImageRef? {
        guard case .image(let ref) = editor.item(id)?.content else { return nil }
        return ref
    }

    private func editedPhoto() -> (CanvasViewModel, CanvasItem.ID, ImageRef) {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addImages([ImageRef(displayName: "roses", fileName: "a.jpg")],
                                  around: CGPoint(x: 150, y: 150))[0]
        let original = ref(editor, id)!
        editor.setImageFilter(itemID: id, to: "mono")
        editor.setImageFrame(itemID: id, to: "polaroid")
        editor.replaceImageFile(itemID: id, fileName: "b.jpg")
        return (editor, id, original)
    }

    func testRestoreBringsBackPixelsFilterAndFrameInOneStep() {
        let (editor, id, original) = editedPhoto()
        let edited = ref(editor, id)

        editor.restoreImage(itemID: id, to: original)
        XCTAssertEqual(ref(editor, id), original)

        editor.undo()
        XCTAssertEqual(ref(editor, id), edited, "one undo returns the edits")
    }

    func testASummaryThatLandedMidSessionSurvivesRevertOfTheSamePixels() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addImages([ImageRef(displayName: "roses", fileName: "a.jpg")],
                                  around: CGPoint(x: 150, y: 150))[0]
        let original = ref(editor, id)!
        editor.setImageSummary(itemID: id, to: "Red roses by a garden sign.")
        editor.setImageFilter(itemID: id, to: "bw")

        editor.restoreImage(itemID: id, to: original)
        XCTAssertEqual(ref(editor, id)?.filterName, "")
        XCTAssertEqual(ref(editor, id)?.summary, "Red roses by a garden sign.",
                       "the pixels never changed, so neither does what they show")
    }

    func testRestoringAnUneditedPhotoRecordsNothing() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addImages([ImageRef(displayName: "roses", fileName: "a.jpg")],
                                  around: CGPoint(x: 150, y: 150))[0]
        let count = editor.changeCount
        editor.restoreImage(itemID: id, to: ref(editor, id)!)
        XCTAssertEqual(editor.changeCount, count)
    }
}
