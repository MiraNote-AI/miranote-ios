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

    func testTheToolBarSwitchesTheRowAbove() {
        startWriting("tools")
        // Aa is the open tool when writing starts (screen 11).
        XCTAssertTrue(app.buttons["style.sizes"].isSelected)
        XCTAssertTrue(app.buttons["style.font.Josefin"].isSelected, "a new block is set in Josefin")

        app.buttons["style.colors"].tap()
        XCTAssertTrue(app.buttons["style.color.#F1EBDD"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["style.font.Josefin"].exists, "one row at a time")
        XCTAssertTrue(app.buttons["style.colors"].isSelected)

        app.buttons["style.ai"].tap()
        XCTAssertTrue(app.buttons["style.ai.original"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["style.ai.original"].isSelected, "the row opens on the words as written")
        XCTAssertFalse(app.buttons["style.color.#F1EBDD"].exists)

        // Align has no row (screens 16-17).
        app.buttons["style.align"].tap()
        waitUntilGone(app.buttons["style.ai.original"], "align closes the open row")
        XCTAssertTrue(app.buttons["style.align"].isSelected)

        app.buttons["style.highlight"].tap()
        XCTAssertTrue(app.buttons["style.highlight.none"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["style.highlight.none"].isSelected, "no background yet")
        XCTAssertFalse(app.buttons["style.align"].isSelected)
    }

    func testTheCustomColorSheetAppliesAHex() {
        startWriting("plum words")
        app.buttons["style.colors"].tap()
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
        app.buttons["style.ai"].tap()
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
    /// back one step at a time, newest first: words typed after a color are
    /// a step of their own, then the color. Both come back, as Cancel's
    /// revert-all did.
    func testUndoRevertsAnEditToAnExistingBlock() {
        startWriting("kept")
        app.buttons["keyboard.done"].tap()
        let block = app.staticTexts["kept"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        let original = textBlock()
        XCTAssertEqual(original["text"] as? String, "kept")

        // Done leaves the block selected: one tap writes again.
        block.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.buttons["style.colors"].tap()
        app.buttons["style.color.#FFFFFF"].tap()
        field.typeText(" more")
        XCTAssertEqual(textBlock()["color"] as? String, "#FFFFFF")

        app.buttons["editor.undo"].tap()
        let afterOne = textBlock()
        XCTAssertEqual(afterOne["text"] as? String, "kept", "the first Undo takes the words back")
        XCTAssertEqual(afterOne["color"] as? String, "#FFFFFF", "and leaves the color, a step of its own")
        app.buttons["editor.undo"].tap()
        let afterTwo = textBlock()
        XCTAssertEqual(afterTwo["color"] as? String, original["color"] as? String, "the second takes the color back")
        app.buttons["keyboard.done"].tap()

        waitUntilGone(field, "Back ends the writing")
        let ended = textBlock()
        XCTAssertEqual(ended["text"] as? String, "kept", "the words as they were")
        XCTAssertEqual(ended["color"] as? String, original["color"] as? String, "in the color they were")
    }

    /// The page's one text block as the -UITEST probe reads it.
    private func textBlock() -> [String: Any] {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        // The probe refreshes every 0.25 s.
        Thread.sleep(forTimeInterval: 0.6)
        let state = (try? JSONSerialization.jsonObject(with: Data(probe.label.utf8)) as? [String: Any]) ?? [:]
        let texts = (state["elements"] as? [[String: Any]] ?? []).filter { $0["kind"] as? String == "text" }
        XCTAssertEqual(texts.count, 1, "one text block on the page")
        return texts.first ?? [:]
    }
}
