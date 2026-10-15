import XCTest

/// The text editor's chrome (handoff screens 10-21): the writing scrim, the
/// tool bar and its rows, the custom color sheet, the in-place AI rewrite
/// and the header's Cancel.
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

    func testTheScrimCoversThePageOnlyWhileWriting() {
        startWriting("under glass")
        let scrim = app.descendants(matching: .any)["text.scrim"]
        XCTAssertTrue(scrim.exists, "the page dims and blurs while words are written")

        app.buttons["keyboard.done"].tap()
        waitUntilGone(scrim, "the scrim lifts when writing ends")
        XCTAssertTrue(app.staticTexts["under glass"].exists)
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
        app.buttons["editor.undo"].tap()
        XCTAssertTrue(app.staticTexts["noodle shop"].waitForExistence(timeout: 5), "one undo takes the rewrite back")
    }

    func testCancelDropsANewBlock() {
        startWriting("never mind")
        app.buttons["text.cancel"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5), "back on the canvas")
        XCTAssertFalse(app.staticTexts["never mind"].exists, "the new block went with the session")
        XCTAssertFalse(app.descendants(matching: .any)["canvas.textEditor"].exists)
    }

    func testCancelRevertsAnEditToAnExistingBlock() {
        startWriting("kept")
        app.buttons["keyboard.done"].tap()
        let block = app.staticTexts["kept"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))

        // Done leaves the block selected: one tap writes again.
        block.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.buttons["style.colors"].tap()
        app.buttons["style.color.#FFFFFF"].tap()
        field.typeText(" more")
        app.buttons["text.cancel"].tap()

        XCTAssertTrue(app.staticTexts["kept"].waitForExistence(timeout: 5), "the words as they were")
        let changed = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "more")).firstMatch
        XCTAssertFalse(changed.exists)
    }
}
