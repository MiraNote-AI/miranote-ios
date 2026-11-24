import XCTest
@testable import MiraNoteKit

/// A push taken back on a saved page (#253): a block that grows over a
/// photo pushes it down, and taken back the photo lands a hair (about
/// 6e-14 pt) off where it was. The page looks as it did, so a saved page
/// left that way stays saved. Before, the exact compare called that hair
/// an edit and Home filed the page as a draft.
@MainActor
final class PushTakenBackTests: XCTestCase {
    func testAVersionTakenBackToOriginalOverAPhotoKeepsASavedPageSaved() throws {
        let saved = savedPageWithBlockAbovePhoto()
        let (id, photo) = (saved.block, saved.photo)
        let editor = CanvasViewModel(memory: saved.page)
        let photoAt = try XCTUnwrap(editor.item(photo)).position
        editor.startEditingText(id)
        let original = try XCTUnwrap(editor.item(id))
        showVersion(editor, id, "Lunch by the river, warm.", height: 100.1)
        XCTAssertGreaterThan(try XCTUnwrap(editor.item(photo)).position.y, photoAt.y + 1,
                             "the version pushed the photo")
        showVersion(editor, id, "lunch", height: original.size.height)
        editor.commitPreview(of: original)
        editor.endEditingText()
        XCTAssertEqual(try XCTUnwrap(editor.item(photo)).position.y, photoAt.y, accuracy: 0.5, "the push taken back")
        XCTAssertFalse(editor.hasEdits)
        XCTAssertFalse(editor.filedMemory(saving: false).isDraft)
    }

    func testWordsThatGrewTheBlockTypedAwayKeepASavedPageSaved() throws {
        let saved = savedPageWithBlockAbovePhoto()
        let (id, photo) = (saved.block, saved.photo)
        let editor = CanvasViewModel(memory: saved.page)
        let photoAt = try XCTUnwrap(editor.item(photo)).position
        editor.startEditingText(id)
        let height = try XCTUnwrap(editor.item(id)).size.height
        // The scene fits the box to the words as they are typed.
        showVersion(editor, id, "lunch by the river, then a long walk home past the old mill", height: 108.9)
        XCTAssertGreaterThan(try XCTUnwrap(editor.item(photo)).position.y, photoAt.y + 1,
                             "the new lines pushed the photo")
        showVersion(editor, id, "lunch", height: height)
        editor.endEditingText()
        XCTAssertEqual(try XCTUnwrap(editor.item(photo)).position.y, photoAt.y, accuracy: 0.5, "the push taken back")
        XCTAssertFalse(editor.hasEdits)
        XCTAssertFalse(editor.filedMemory(saving: false).isDraft)
    }

    // A drag released a point or more from where it started is a move.
    func testMovingAPhotoAPointIsStillAnEdit() throws {
        let saved = savedPageWithBlockAbovePhoto()
        let editor = CanvasViewModel(memory: saved.page)
        let photoAt = try XCTUnwrap(editor.item(saved.photo)).position
        editor.beginChange()
        editor.move(itemID: saved.photo, to: CGPoint(x: photoAt.x, y: photoAt.y + 1))
        XCTAssertTrue(editor.hasEdits)
        XCTAssertTrue(editor.filedMemory(saving: false).isDraft)
    }

    func testAVersionKeptOverAPhotoIsAnEdit() throws {
        let saved = savedPageWithBlockAbovePhoto()
        let id = saved.block
        let editor = CanvasViewModel(memory: saved.page)
        editor.startEditingText(id)
        let original = try XCTUnwrap(editor.item(id))
        showVersion(editor, id, "Lunch by the river, warm.", height: 100.1)
        editor.commitPreview(of: original)
        editor.endEditingText()
        XCTAssertTrue(editor.hasEdits)
        XCTAssertTrue(editor.filedMemory(saving: false).isDraft)
    }

    func testADraftWithAPushTakenBackStaysADraft() throws {
        var draft = savedPageWithBlockAbovePhoto()
        draft.page.isDraft = true
        let id = draft.block
        let editor = CanvasViewModel(memory: draft.page)
        editor.startEditingText(id)
        let original = try XCTUnwrap(editor.item(id))
        showVersion(editor, id, "Lunch by the river, warm.", height: 100.1)
        showVersion(editor, id, "lunch", height: original.size.height)
        editor.commitPreview(of: original)
        editor.endEditingText()
        XCTAssertTrue(editor.filedMemory(saving: false).isDraft)
    }

    /// New words in block `id`, then its box fitted to them, as the AI row
    /// and typing do: a box that grows pushes what is below it.
    private func showVersion(_ editor: CanvasViewModel, _ id: CanvasItem.ID, _ text: String, height: CGFloat) {
        editor.setText(itemID: id, to: text)
        editor.autosizeTextHeight(itemID: id, to: height)
    }

    private struct BlockAbovePhoto {
        var page: Memory
        let block: CanvasItem.ID
        let photo: CanvasItem.ID
    }

    /// A page saved with a one-line text block above a photo, as a page
    /// written, saved and opened again.
    private func savedPageWithBlockAbovePhoto() -> BlockAbovePhoto {
        let writing = CanvasViewModel(memory: Memory(isDraft: true))
        let block = writing.addText("lunch", at: CGPoint(x: 120, y: 100.3))
        writing.autosizeTextHeight(itemID: block, to: 36.3)
        let photo = writing.addImages([ImageRef(displayName: "p")], around: CGPoint(x: 120, y: 300.3))[0]
        let page = writing.leave(saving: true)
        XCTAssertFalse(page.isDraft)
        return BlockAbovePhoto(page: page, block: block, photo: photo)
    }
}
