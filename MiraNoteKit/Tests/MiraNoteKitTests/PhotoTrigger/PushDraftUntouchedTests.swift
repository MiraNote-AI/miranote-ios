import XCTest
@testable import MiraNoteKit

/// A push draft left as it arrived is not saved (user decision 2026-11-01):
/// "as it arrived" is the page's content, not how many steps were taken.
@MainActor
final class PushDraftUntouchedTests: XCTestCase {
    private func draft() -> TriggerDraft {
        let ids = ["P1", "P2", "P3"]
        let base = TriggerMemoryTests.memory(ids: ids, peak: "P1")
        let memory = TriggerMemory(
            id: "m", date: "2026-10-18", daypart: .afternoon, bucket: "b", push: base.push, story: base.story,
            ending: .init(factLine: "10.18 Arboretum", detail: "Light on the arch",
                          questions: [.init(text: "What else?", type: "zoom", source: "llm")], ctaLabel: "Keep"))
        return TriggerDraftBuilder.draft(memory: memory,
                                         imageFiles: ["P1": "a.png", "P2": "b.png", "P3": "c.png"], detailFont: "X")
    }

    private func canvas() -> (CanvasViewModel, TriggerDraft) {
        let draft = draft()
        return (CanvasViewModel(memory: draft.page, prompts: draft.prompts), draft)
    }

    private func photo(_ draft: TriggerDraft) throws -> CanvasItem {
        try XCTUnwrap(draft.page.items.first { if case .image = $0.content { return true }; return false })
    }

    /// Drags a photo by `distance` points, as the board's move gesture does.
    private func drag(_ item: CanvasItem, by distance: CGFloat, on canvas: CanvasViewModel) {
        canvas.beginChange()
        canvas.move(itemID: item.id, to: CGPoint(x: item.position.x + distance, y: item.position.y))
    }

    func testFreshDraftIsAsArrived() {
        XCTAssertTrue(canvas().0.isAsArrived)
    }

    func testOpeningATextBlockWithoutTypingIsAsArrived() throws {
        let (canvas, draft) = canvas()
        let question = try XCTUnwrap(draft.prompts.keys.first)
        canvas.select(question)
        canvas.startEditingText(question)
        XCTAssertTrue(canvas.isAsArrived, "a block open for writing, nothing typed")
        canvas.endEditingText()
        XCTAssertTrue(canvas.isAsArrived)
    }

    func testUndoBackToTheStartIsAsArrived() throws {
        let (canvas, draft) = canvas()
        drag(try photo(draft), by: 120, on: canvas)
        XCTAssertFalse(canvas.isAsArrived)
        canvas.undo()
        XCTAssertTrue(canvas.isAsArrived)
    }

    func testTypingThenErasingBackIsAsArrived() throws {
        let (canvas, draft) = canvas()
        let question = try XCTUnwrap(draft.prompts.keys.first)
        canvas.startEditingText(question)
        canvas.setText(itemID: question, to: "What else? Rain")
        XCTAssertFalse(canvas.isAsArrived)
        canvas.setText(itemID: question, to: "What else?")
        XCTAssertTrue(canvas.isAsArrived)
    }

    func testStrayMoveIsAsArrived() throws {
        let (canvas, draft) = canvas()
        drag(try photo(draft), by: 4, on: canvas)
        XCTAssertTrue(canvas.isAsArrived, "a finger that slid 4 pt while tapping")
        XCTAssertEqual(CanvasViewModel.strayMoveDistance, 8)
    }

    func testRealMoveIsAChange() throws {
        let (canvas, draft) = canvas()
        drag(try photo(draft), by: 8, on: canvas)
        XCTAssertFalse(canvas.isAsArrived)
    }

    func testWordsAreAChange() throws {
        let (canvas, draft) = canvas()
        let question = try XCTUnwrap(draft.prompts.keys.first)
        canvas.setText(itemID: question, to: "What else? Rain")
        XCTAssertFalse(canvas.isAsArrived)
    }

    func testANewBlockStillEmptyIsAsArrived() {
        let (canvas, _) = canvas()
        let id = canvas.addText("", at: CGPoint(x: 100, y: 900))
        canvas.startEditingText(id, recordingUndo: false)
        XCTAssertTrue(canvas.isAsArrived, "nothing written in it yet")
        canvas.setText(itemID: id, to: "hello")
        XCTAssertFalse(canvas.isAsArrived)
    }

    func testDeletingIsAChange() throws {
        let (canvas, draft) = canvas()
        canvas.delete(itemID: try photo(draft).id)
        XCTAssertFalse(canvas.isAsArrived)
    }

    func testPageColorIsAChangeButAPreviewIsNot() {
        let (canvas, _) = canvas()
        let original = canvas.pageLook
        canvas.setPageColor("sage", recordingUndo: false)
        XCTAssertTrue(canvas.isAsArrived, "only previewed")
        canvas.commitPagePreview(from: original)
        XCTAssertFalse(canvas.isAsArrived)
    }

    /// The page's own work never counts: a photo's description landing, and
    /// the open's re-measure of text that pushes what is below it.
    func testThePagesOwnLayoutIsAsArrived() throws {
        let (canvas, draft) = canvas()
        canvas.setImageSummary(itemID: try photo(draft).id, to: "a bench under the arch")
        canvas.fitTextHeights { item in
            if case .text = item.content { return item.size.height + 40 }
            return nil
        }
        XCTAssertNotEqual(canvas.memory.items, draft.page.items, "the fit moved things")
        XCTAssertTrue(canvas.isAsArrived)
        // A real move after the fit still counts, a stray one still does not.
        let moved = try XCTUnwrap(canvas.items.first { $0.id == (try? photo(draft).id) })
        drag(moved, by: 4, on: canvas)
        XCTAssertTrue(canvas.isAsArrived)
        drag(moved, by: 30, on: canvas)
        XCTAssertFalse(canvas.isAsArrived)
    }
}
