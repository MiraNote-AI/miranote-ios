import XCTest

/// The text editor's chrome (handoff screens 10-21, #205): the clear page
/// and the waiting header, the tool bar and its rows, the custom color
/// sheet, the in-place AI rewrite, and Undo and Back.
final class TextEditorUITests: XCTestCase {
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

    private var field: XCUIElement { app.descendants(matching: .any)["canvas.textEditor"] }

    private func startWriting(_ words: String) {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
    }

    private func waitUntilGone(_ element: XCUIElement, _ message: String) {
        XCTAssertTrue(element.waitForNonExistence(timeout: 10), message)
    }

    private func replace(_ textField: XCUIElement, with text: String) {
        textField.tap()
        let current = (textField.value as? String) ?? ""
        textField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 1))
        textField.typeText(text)
    }

    /// #205: the page stays clear while words are written; the header
    /// greys Home and Save until the row's Back ends the writing.
    func testThePageStaysClearAndTheHeaderWaitsWhileWriting() {
        startWriting("on a clear page")
        XCTAssertFalse(app.descendants(matching: .any)["text.scrim"].exists, "no scrim over the page")
        XCTAssertFalse(app.buttons["nav.leading"].isEnabled, "Home waits for the writing to end")
        XCTAssertFalse(app.buttons["nav.trailing"].isEnabled, "Save waits for the writing to end")
        XCTAssertEqual(app.buttons["keyboard.done"].label, "Back")

        app.buttons["keyboard.done"].tap()
        waitUntilGone(field, "Back ends the writing")
        XCTAssertTrue(app.staticTexts["on a clear page"].exists)
        XCTAssertTrue(app.buttons["nav.leading"].isEnabled, "Home is back")
        XCTAssertTrue(app.buttons["nav.trailing"].isEnabled, "Save is back")
    }

    /// Esc on a hardware keyboard ends the writing, as Back does (R1A).
    /// XCUITest's typeKey goes through the software keyboard, never as a
    /// hardware key, so this checks Esc's key command is armed exactly while
    /// words are written (a real Esc was checked by hand on the simulator).
    func testEscapeIsArmedOnlyWhileWriting() {
        startWriting("escaped")
        XCTAssertTrue(escapeArmed(), "Esc is armed while writing")
        app.buttons["keyboard.done"].tap()
        waitUntilGone(field, "Back ends the writing")
        XCTAssertFalse(escapeArmed(), "Esc is let go once the writing ends")
    }

    private func escapeArmed() -> Bool {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        // The probe refreshes every 0.25 s.
        Thread.sleep(forTimeInterval: 0.6)
        return probe.label.contains("\"escapeArmed\":true")
    }

    /// One row in the text slot (#205): each tool's row takes the text
    /// row's place, and its own Back goes back to it.
    func testEachToolRowReplacesTheTextRow() {
        startWriting("tools")
        // Writing starts on the text row (S7).
        XCTAssertTrue(app.buttons["style.font"].exists)
        XCTAssertFalse(app.buttons["text.row.back"].exists)

        app.openTextRow("style.font")
        XCTAssertTrue(app.buttons["style.font.Josefin"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["style.font.Josefin"].isSelected, "a new block is set in Josefin")
        XCTAssertFalse(app.buttons["style.colors"].exists, "the font row is in the text row's place")
        XCTAssertFalse(app.buttons["keyboard.done"].exists, "its Back goes up a level, not out")

        app.openTextRow("style.colors")
        XCTAssertTrue(app.buttons["style.color.#F1EBDD"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["style.font.Josefin"].exists, "one row at a time")

        app.openTextRow("style.ai")
        XCTAssertTrue(app.buttons["style.ai.original"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["style.ai.original"].isSelected, "the row opens on the words as written")
        XCTAssertFalse(app.buttons["style.color.#F1EBDD"].exists)

        // Align has no row (screens 16-17): it steps on the text row.
        app.backToTextRow()
        waitUntilGone(app.buttons["style.ai.original"], "Back closes the row")
        app.buttons["style.align"].tap()
        XCTAssertEqual(app.buttons["style.align"].value as? String, "Centered")
        XCTAssertFalse(app.buttons["text.row.back"].exists, "align opens no row")

        app.openTextRow("style.highlight")
        XCTAssertTrue(app.buttons["style.highlight.none"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["style.highlight.none"].isSelected, "no background yet")
        XCTAssertFalse(app.buttons["style.align"].exists)
    }

    func testTheCustomColorSheetAppliesAHex() {
        startWriting("plum words")
        app.openTextRow("style.colors")
        app.buttons["style.color.custom"].tap()
        let hex = app.textFields["colorSheet.hex"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        replace(hex, with: "8B5962")
        hex.typeText("\n")
        app.buttons["colorSheet.apply"].tap()
        waitUntilGone(app.buttons["colorSheet.apply"], "Apply closes the sheet")
        let custom = app.buttons["style.color.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 2))
        XCTAssertTrue(custom.isSelected, "the applied custom color is the block's color")

        // Reopened, the sheet starts from it; a tap outside drops a change.
        custom.tap()
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        XCTAssertEqual(hex.value as? String, "#8B5962")
        replace(hex, with: "112233")
        hex.typeText("\n")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        waitUntilGone(app.buttons["colorSheet.apply"], "a tap outside closes the sheet")
        custom.tap()
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        XCTAssertEqual(hex.value as? String, "#8B5962", "the cancelled change was not kept")
    }

    func testOriginalBringsTheWordsBackAfterARewrite() {
        startWriting("noodle shop")
        app.openTextRow("style.ai")
        app.buttons["style.ai.expand"].tap()
        expectation(for: NSPredicate(format: "value CONTAINS %@", "(expanded draft -- mock)"), evaluatedWith: field)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["style.ai.expand"].isSelected)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the rewrite happens in place, still writing")

        app.buttons["style.ai.original"].tap()
        XCTAssertEqual(field.value as? String, "noodle shop")
        XCTAssertTrue(app.buttons["style.ai.original"].isSelected)

        // Kept on Done as one undo step.
        app.buttons["style.ai.expand"].tap()
        expectation(for: NSPredicate(format: "value CONTAINS %@", "(expanded draft -- mock)"), evaluatedWith: field)
        waitForExpectations(timeout: 5)
        app.backToTextRow()
        app.buttons["keyboard.done"].tap()
        let expanded = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "expanded draft")).firstMatch
        XCTAssertTrue(expanded.waitForExistence(timeout: 5))
        // The mock's expansion is a paragraph of its own, which Done splits
        // into a block (#184): one undo joins it back, the next takes the
        // rewrite back.
        app.buttons["editor.undo"].tap()
        app.buttons["editor.undo"].tap()
        XCTAssertTrue(app.staticTexts["noodle shop"].waitForExistence(timeout: 5), "the undo takes the rewrite back")
        XCTAssertFalse(expanded.exists)
    }

    /// No Cancel while writing (#205): Undo takes a new block back.
    func testUndoTakesANewBlockBack() {
        startWriting("never mind")
        app.buttons["editor.undo"].tap()
        if app.buttons["keyboard.done"].exists { app.buttons["keyboard.done"].tap() }
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5), "back on the canvas")
        XCTAssertFalse(app.staticTexts["never mind"].exists, "the new block went with the undo")
        XCTAssertFalse(app.descendants(matching: .any)["canvas.textEditor"].exists)
    }

    /// Undo while writing takes the session's edits to an existing block
    /// back in one step.
    func testUndoRevertsAnEditToAnExistingBlock() {
        startWriting("kept")
        app.buttons["keyboard.done"].tap()
        let block = app.staticTexts["kept"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))

        // Done leaves the block selected: one tap writes again.
        block.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.openTextRow("style.colors")
        app.buttons["style.color.#FFFFFF"].tap()
        field.typeText(" more")
        app.buttons["editor.undo"].tap()
        app.backToTextRow()
        app.buttons["keyboard.done"].tap()

        XCTAssertTrue(app.staticTexts["kept"].waitForExistence(timeout: 5), "the words as they were")
        let changed = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "more")).firstMatch
        XCTAssertFalse(changed.exists)
    }
}
