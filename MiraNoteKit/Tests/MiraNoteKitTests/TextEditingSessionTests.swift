import XCTest
@testable import MiraNoteKit

/// The text editor's session rules (handoff screens 10-21): Cancel takes the
/// session back, previews commit as one undo step, AI rewrites are cached.
@MainActor
final class TextEditingSessionTests: XCTestCase {
    private func block(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> TextBlock? {
        guard case .text(let block) = editor.item(id)?.content else { return nil }
        return block
    }

    // MARK: Cancel

    func testCancelOnANewBlockRemovesIt() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("", at: CGPoint(x: 100, y: 100))
        editor.startEditingText(id, recordingUndo: false)
        editor.setText(itemID: id, to: "half a thought")
        editor.setTextFont(itemID: id, to: "Futura")

        editor.cancelEditingText()
        XCTAssertNil(editor.item(id), "the block the session made is gone")
        XCTAssertNil(editor.editingTextItemID)
        XCTAssertFalse(editor.canUndo, "and so are the session's undo steps")
    }

    func testCancelRestoresAnExistingBlocksWordsAndStyle() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("kept words", at: CGPoint(x: 100, y: 100))
        editor.startEditingText(id)
        editor.setText(itemID: id, to: "kept words, then more")
        editor.setTextColorName(itemID: id, to: "#FFFFFF")
        editor.setTextAlignment(itemID: id, to: .center)

        editor.cancelEditingText()
        XCTAssertEqual(block(editor, id)?.text, "kept words")
        XCTAssertEqual(block(editor, id)?.colorName, "ink")
        XCTAssertEqual(block(editor, id)?.alignment, .leading)
        editor.undo()
        XCTAssertNil(editor.item(id), "the next undo is the step before the session")
    }

    func testCancelAfterUndoingPastTheSessionStartChangesNothingMore() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("first", at: CGPoint(x: 100, y: 100))
        editor.startEditingText(id)
        editor.setTextColorName(itemID: id, to: "#FFFFFF")
        editor.undo()
        editor.undo()
        XCTAssertEqual(block(editor, id)?.colorName, "ink")

        editor.cancelEditingText()
        XCTAssertEqual(block(editor, id)?.text, "first", "the earlier step is not eaten")
        XCTAssertTrue(editor.canUndo)
    }

    func testCancelKeepsWhatLandedElsewhereDuringTheSession() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("lunch", at: CGPoint(x: 100, y: 100))
        editor.startEditingText(id)
        editor.setText(itemID: id, to: "lunch with Sam")
        editor.setTextPointSize(itemID: id, to: 30)
        // A Mira backdrop finishes while the user writes.
        editor.setBackground(fileName: "dusk.png")
        editor.setText(itemID: id, to: "lunch with Sam and Jo")

        editor.cancelEditingText()
        XCTAssertEqual(editor.memory.backgroundFileName, "dusk.png", "the painting is not the session's")
        XCTAssertEqual(block(editor, id)?.text, "lunch")
        XCTAssertEqual(block(editor, id)?.pointSize, 17)
        editor.undo()
        XCTAssertEqual(editor.memory.backgroundFileName, "", "the painting is still its own undo step")
        XCTAssertEqual(block(editor, id)?.text, "lunch", "with the block as before the session")
        editor.undo()
        XCTAssertNil(editor.item(id), "then the step before the session")
    }

    func testCancelOnANewBlockKeepsAnotherElementsChange() {
        let editor = CanvasViewModel(memory: Memory())
        let photo = editor.addImages(
            [ImageRef(displayName: "a", fileName: "a.jpg")], around: CGPoint(x: 100, y: 300)
        )[0]
        let id = editor.addText("", at: CGPoint(x: 100, y: 100))
        editor.startEditingText(id, recordingUndo: false)
        editor.setText(itemID: id, to: "caption")
        editor.replaceImageFile(itemID: photo, fileName: "ai.jpg")

        editor.cancelEditingText()
        XCTAssertNil(editor.item(id))
        guard case .image(let ref) = editor.item(photo)?.content else { return XCTFail("photo gone") }
        XCTAssertEqual(ref.fileName, "ai.jpg", "a photo AI edit that landed meanwhile stays")
    }

    func testDoneKeepsTheSession() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("", at: CGPoint(x: 100, y: 100))
        editor.startEditingText(id, recordingUndo: false)
        editor.setText(itemID: id, to: "stays")
        editor.endEditingText()
        editor.cancelEditingText()
        XCTAssertEqual(block(editor, id)?.text, "stays", "Cancel after Done has no session to revert")
    }

    // MARK: Previews

    func testAPreviewCommitsAsOneUndoStep() throws {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("raw", at: CGPoint(x: 100, y: 100))
        let original = try XCTUnwrap(editor.item(id))
        editor.setText(itemID: id, to: "cleaned")
        editor.setText(itemID: id, to: "expanded")
        let countBefore = editor.changeCount

        editor.commitPreview(of: original)
        XCTAssertEqual(block(editor, id)?.text, "expanded")
        XCTAssertEqual(editor.changeCount, countBefore + 1)
        editor.undo()
        XCTAssertEqual(block(editor, id)?.text, "raw", "one undo takes the whole preview back")
    }

    func testAnUnchangedPreviewRecordsNothing() throws {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("raw", at: CGPoint(x: 100, y: 100))
        let original = try XCTUnwrap(editor.item(id))
        editor.setTextColorName(itemID: id, to: "#E5AC95", recordingUndo: false)
        editor.setTextColorName(itemID: id, to: "ink", recordingUndo: false)
        let countBefore = editor.changeCount

        editor.commitPreview(of: original)
        XCTAssertEqual(editor.changeCount, countBefore)
    }

    func testADiscardedPreviewLeavesNoTrace() throws {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("raw", at: CGPoint(x: 100, y: 100))
        let original = try XCTUnwrap(editor.item(id))
        editor.setTextBackground(itemID: id, to: "#8B5962", recordingUndo: false)
        let countBefore = editor.changeCount

        editor.discardPreview(of: original)
        XCTAssertEqual(block(editor, id)?.backgroundColorName, "")
        XCTAssertEqual(editor.changeCount, countBefore)
    }

    // MARK: AI rewrite

    func testRewritesAreCachedAndOriginalComesBack() {
        var session = TextRewriteSession(original: "sunny noodle shop")
        XCTAssertEqual(session.selected, .original)
        XCTAssertNil(session.select(.clean), "first time: has to be fetched")
        XCTAssertEqual(session.pending, .clean)
        XCTAssertEqual(session.resolve(.clean, of: "sunny noodle shop", with: "Sunny noodle shop."),
                       "Sunny noodle shop.")
        XCTAssertEqual(session.selected, .clean)

        XCTAssertEqual(session.select(.original), "sunny noodle shop")
        XCTAssertEqual(session.select(.clean), "Sunny noodle shop.", "second time: from the cache")
    }

    func testALateRewriteIsCachedButNotShown() {
        var session = TextRewriteSession(original: "words")
        _ = session.select(.expand)
        _ = session.select(.original)
        XCTAssertNil(session.resolve(.expand, of: "words", with: "many words"), "the user moved on")
        XCTAssertEqual(session.selected, .original)
        XCTAssertEqual(session.select(.expand), "many words")
    }

    func testTypingMakesANewOriginalAndDropsStaleRewrites() {
        var session = TextRewriteSession(original: "words")
        _ = session.select(.clean)
        _ = session.resolve(.clean, of: "words", with: "Words.")
        session.adopt(typed: "Words. And more")
        XCTAssertEqual(session.original, "Words. And more")
        XCTAssertEqual(session.selected, .original)
        XCTAssertNil(session.text(for: .clean))

        _ = session.select(.expand)
        XCTAssertNil(session.resolve(.expand, of: "words", with: "stale"), "a rewrite of the old words")
        XCTAssertNil(session.text(for: .expand))
    }

    func testShowingARewriteIsNotTyping() {
        var session = TextRewriteSession(original: "words")
        _ = session.select(.clean)
        _ = session.resolve(.clean, of: "words", with: "Words.")
        session.adopt(typed: "Words.")
        XCTAssertEqual(session.original, "words", "the binding echoing the preview changes nothing")
    }

    func testAFailedRewriteKeepsTheSelection() {
        var session = TextRewriteSession(original: "words")
        _ = session.select(.clean)
        session.fail(.clean, of: "words")
        XCTAssertNil(session.pending)
        XCTAssertEqual(session.selected, .original)
    }

    // MARK: Color field

    func testHexRoundTrips() {
        XCTAssertEqual(RGBColor(hex: "#e5ac95")?.hex, "#E5AC95")
        XCTAssertEqual(RGBColor(hex: "8B5962")?.hex, "#8B5962")
        XCTAssertNil(RGBColor(hex: "#8B596"))
        XCTAssertNil(RGBColor(hex: "#GGGGGG"))
    }

    func testTheRestingFieldIsTheDrawnSpectrum() {
        // Top-left: cream under the white veil; bottom-right: teal sunk
        // toward forest.
        XCTAssertEqual(ColorField.color(x: 0, y: 0, rail: ColorField.restingRail).hex, "#FFF9EA")
        let bottomRight = ColorField.color(x: 1, y: 1, rail: ColorField.restingRail)
        let expected = RGBColor(hex: 0x719B8E).mixed(with: RGBColor(hex: 0x24382D), amount: 0.58)
        XCTAssertEqual(bottomRight.hex, expected.hex)
    }

    func testTheRailTurnsTheHue() {
        let rested = ColorField.color(x: 0.4, y: 0.3, rail: ColorField.restingRail)
        let turned = ColorField.color(x: 0.4, y: 0.3, rail: ColorField.restingRail + 0.5)
        XCTAssertNotEqual(rested.hex, turned.hex)
    }

    // The handoff's two custom colors, a field color and a turned one.
    func testNearestFindsAPositionThatShowsTheColor() {
        for hex in ["#E5AC95", "#8B5962", "#719B8E", "#95B4E5"] {
            let target = RGBColor(hex: hex)!
            let spot = ColorField.nearest(to: target)
            let shown = ColorField.color(x: spot.x, y: spot.y, rail: spot.rail)
            XCTAssertLessThan(shown.distance(to: target), 0.01, "\(hex) shows as \(shown.hex)")
        }
    }
}
