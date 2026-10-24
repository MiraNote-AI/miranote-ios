import XCTest
@testable import MiraNoteKit

/// Draft and saved pages (#137): Save is the one way a page becomes saved;
/// leaving any other way keeps it a draft -- except a saved page that
/// leaves unchanged.
@MainActor
final class DraftPageTests: XCTestCase {
    // MARK: The stored flag

    func testAPageSavedBeforeDraftsExistedLoadsAsSaved() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000003","title":"old page",
         "body":"","createdAt":700000000,"memoryDate":700000000,"items":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let memory = try decoder.decode(Memory.self, from: Data(legacy.utf8))
        XCTAssertFalse(memory.isDraft, "pages from before this change count as saved")
    }

    func testADraftStaysADraftThroughARoundTrip() throws {
        let draft = Memory(title: "half a thought", isDraft: true)
        let back = try JSONDecoder().decode(Memory.self, from: JSONEncoder().encode(draft))
        XCTAssertTrue(back.isDraft)
    }

    func testANewMemoryIsSavedUnlessMarked() {
        XCTAssertFalse(Memory(title: "seeded").isDraft, "seeds and old call sites stay saved")
    }

    // MARK: An edit, or just a look

    func testOpeningAPageIsNoEdit() {
        XCTAssertFalse(CanvasViewModel(memory: savedPage()).hasEdits)
    }

    func testTheOpeningRemeasureIsNoEdit() {
        let editor = CanvasViewModel(memory: savedPage())
        editor.fitTextHeights { _ in 120 }
        XCTAssertFalse(editor.hasEdits, "the app fitting its text boxes is not the user's edit")
    }

    func testTappingIntoWordsWithoutTypingIsNoEdit() {
        let page = savedPage()
        let editor = CanvasViewModel(memory: page)
        editor.startEditingText(page.items[0].id)
        editor.endEditingText()
        XCTAssertFalse(editor.hasEdits)
    }

    func testTypingIsAnEdit() {
        let page = savedPage()
        let editor = CanvasViewModel(memory: page)
        let id = page.items[0].id
        editor.startEditingText(id)
        editor.setText(itemID: id, to: "Lunch by the sea")
        editor.endEditingText()
        XCTAssertTrue(editor.hasEdits)
    }

    func testAnEditUndoneIsNoEdit() {
        let editor = CanvasViewModel(memory: savedPage())
        editor.addText("a second coffee", at: CGPoint(x: 100, y: 500))
        XCTAssertTrue(editor.hasEdits)
        editor.undo()
        XCTAssertFalse(editor.hasEdits, "back to the page as it was")
    }

    // A photo saved before its description came back is described again
    // when the page opens; that landing is no edit (as for undo, #101).
    func testAPhotoDescriptionLandingAfterALookIsNoEdit() {
        let (page, photo) = savedPageWithPhoto()
        let editor = CanvasViewModel(memory: page)
        editor.startEditingText(page.items[0].id)
        editor.endEditingText()
        editor.setImageSummary(itemID: photo, to: "a bowl of noodles")
        XCTAssertFalse(editor.hasEdits)
        XCTAssertFalse(editor.filedMemory(saving: false).isDraft)
    }

    func testAPhotoDescriptionLandingAfterAnUndoneEditIsNoEdit() {
        let (page, photo) = savedPageWithPhoto()
        let editor = CanvasViewModel(memory: page)
        editor.addText("a second coffee", at: CGPoint(x: 100, y: 800))
        editor.undo()
        editor.setImageSummary(itemID: photo, to: "a bowl of noodles")
        XCTAssertFalse(editor.hasEdits)
    }

    // An empty block an older build filed is swept when a text session
    // ends (the scene's clean-up); the app tidying it is no edit.
    func testSweepingAnOldEmptyBlockIsNoEdit() {
        var page = savedPage()
        let husk = CanvasItem(
            content: .text(TextBlock(text: " ")),
            position: CGPoint(x: 100, y: 700),
            size: CGSize(width: 200, height: 40),
            zIndex: 9
        )
        page.items.append(husk)
        let editor = CanvasViewModel(memory: page)
        editor.startEditingText(page.items[0].id)
        editor.endEditingText()
        editor.discardAbandonedText(itemID: husk.id)
        XCTAssertFalse(editor.hasEdits)
    }

    // MARK: The way out

    // Save files the page and the editor starts closing; the app reaching
    // the background before it is gone must not refile it as a draft.
    func testTheAutosaveFilesNothingOnceTheEditorIsLeft() {
        let editor = CanvasViewModel(memory: Memory(isDraft: true))
        editor.addText("picnic", at: CGPoint(x: 100, y: 100))
        XCTAssertFalse(editor.leave(saving: true).isDraft)
        XCTAssertNil(editor.autosavedMemory)
    }

    func testTheAutosaveKeepsADraftWhileTheEditorIsOpen() {
        let editor = CanvasViewModel(memory: Memory(isDraft: true))
        editor.addText("picnic", at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(editor.autosavedMemory?.isDraft, true)
    }

    // MARK: What leaving files

    func testSaveFilesASavedPage() {
        let editor = CanvasViewModel(memory: Memory(isDraft: true))
        editor.addText("picnic", at: CGPoint(x: 100, y: 100))
        XCTAssertFalse(editor.filedMemory(saving: true).isDraft)
    }

    func testLeavingANewPageKeepsItADraft() {
        let editor = CanvasViewModel(memory: Memory(isDraft: true))
        editor.addText("picnic", at: CGPoint(x: 100, y: 100))
        XCTAssertTrue(editor.filedMemory(saving: false).isDraft)
    }

    func testLeavingASavedPageUnchangedKeepsItSaved() {
        let editor = CanvasViewModel(memory: savedPage())
        XCTAssertFalse(editor.filedMemory(saving: false).isDraft)
    }

    func testLeavingAChangedSavedPageMakesItADraft() {
        let editor = CanvasViewModel(memory: savedPage())
        editor.addText("a second coffee", at: CGPoint(x: 100, y: 500))
        XCTAssertTrue(editor.filedMemory(saving: false).isDraft)
    }

    func testLeavingADraftUnchangedKeepsItADraft() {
        var page = savedPage()
        page.isDraft = true
        XCTAssertTrue(CanvasViewModel(memory: page).filedMemory(saving: false).isDraft)
    }

    private func savedPage() -> Memory {
        Memory(title: "Lunch by the river", items: Memory.starterDraft())
    }

    /// A saved page holding a photo that has no description yet.
    private func savedPageWithPhoto() -> (Memory, CanvasItem.ID) {
        var page = savedPage()
        let photo = CanvasItem(
            content: .image(ImageRef(displayName: "noodles", fileName: "noodles.jpg")),
            position: CGPoint(x: 180, y: 600),
            size: CGSize(width: 170, height: 150),
            zIndex: 9
        )
        page.items.append(photo)
        return (page, photo.id)
    }
}
