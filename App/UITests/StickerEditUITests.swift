import XCTest

/// Editing a placed sticker: the Mira ask and the long-press panel
/// (deterministic under -UITEST: the mock studio answers instantly).
final class StickerEditUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func startMemory() {
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    private func ask(_ words: String) {
        app.askMira(words)
    }

    /// Draw-and-place one sticker, then Keep the placement (the result
    /// sheet waits for a choice) so the next step starts from a quiet strip.
    private func placeOneSticker() {
        ask("draw a sticker of a coffee cup")
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 5))
        let keep = app.buttons["mira.keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        keep.tap()
        let receipt = app.staticTexts["mira.receipt"]
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: receipt)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed,
                       "Keep clears the result sheet")
    }

    func testAskRestylesThePlacedSticker() {
        startMemory()
        placeOneSticker()

        ask("make the sticker blue")
        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 8),
                      "the edit lands with a receipt")
        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        XCTAssertTrue(sticker.exists, "the element is still a sticker")
    }

    /// The panel's header Undo has none of its own steps to take back, so
    /// it never reaches the canvas under it (the sticker's placement).
    func testThePanelsHeaderUndoLeavesTheCanvasAlone() {
        startMemory()
        placeOneSticker()
        XCTAssertTrue(app.buttons["editor.undo"].isEnabled, "the placement can be undone from the canvas")

        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        sticker.press(forDuration: 1.1)
        let entry = app.buttons["Edit sticker"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.textFields["sticker.ai.instruction"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled, "the panel's Undo would take the sticker away")
    }

    func testLongPressPanelEditsTheSticker() {
        startMemory()
        placeOneSticker()

        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        sticker.press(forDuration: 1.1)
        let entry = app.buttons["Edit sticker"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "the menu gains Edit sticker")
        entry.tap()

        let field = app.textFields["sticker.ai.instruction"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("make it blue")
        app.buttons["sticker.ai.run"].tap()
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 8), .completed,
                       "the panel closes itself once the swap lands")
        let edited = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 5), "the element is still a sticker")
        XCTAssertTrue(edited.isHittable, "the edited sticker is on screen, no scrolling needed")
    }

    /// Edit sticker offers AI Editing and Outline, like Photo Editing but only
    /// those two; Outline adds the white edge in place, one undo.
    func testOutlineTileEdgesTheStickerInPlace() {
        startMemory()
        placeOneSticker()

        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        sticker.press(forDuration: 1.1)
        let entry = app.buttons["Edit sticker"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        XCTAssertTrue(app.buttons["sticker.tile.ai"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sticker.tile.ai"].isSelected, "AI Editing owns the composer")
        let outline = app.buttons["sticker.tile.outline"]
        XCTAssertTrue(outline.exists)
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sticker.tile.'"))
        XCTAssertEqual(tiles.count, 2, "exactly two tiles: no Cutout, filters or frames here")
        outline.tap()

        let field = app.textFields["sticker.ai.instruction"]
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 8), .completed,
                       "the panel closes once the outlined sticker lands")
        let outlined = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        XCTAssertTrue(outlined.waitForExistence(timeout: 5), "still a sticker, in place")
        let undo = app.buttons["editor.undo"]
        XCTAssertTrue(undo.isEnabled, "one undo takes the edge back off")
        undo.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch.waitForExistence(timeout: 5),
                      "undo restores the sticker, not an empty page")
    }
}
