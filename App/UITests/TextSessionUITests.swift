import XCTest

/// The text session's edges (review of #105): header undo with the custom
/// color sheet up, the custom background's Apply, and the dictation strip
/// beside a live voice take.
final class TextSessionUITests: XCTestCase {
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

    private func tapText(_ words: String) {
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
    }

    func testHeaderUndoWithTheColorSheetUpOnlyDropsThePreview() {
        app.buttons["Start a memory"].tap()
        tapText("restyle me")
        app.buttons["style.font.Futura"].tap()
        XCTAssertTrue(app.buttons["style.font.Futura"].isSelected)

        app.buttons["style.colors"].tap()
        app.buttons["style.color.custom"].tap()
        let hex = app.textFields["colorSheet.hex"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        hex.tap()
        let current = (hex.value as? String) ?? ""
        hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 1))
        hex.typeText("112233\n")

        app.buttons["editor.undo"].tap()
        XCTAssertTrue(app.buttons["colorSheet.apply"].waitForNonExistence(timeout: 5), "undo closes the sheet")
        app.buttons["style.sizes"].tap()
        XCTAssertTrue(app.buttons["style.font.Futura"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["style.font.Futura"].isSelected, "the font step before the preview stays")
        XCTAssertTrue(field.exists, "and so does the block")
    }

    func testCustomBackgroundApplyKeepsTheShownColor() {
        app.buttons["Start a memory"].tap()
        tapText("on plum")
        app.buttons["style.highlight"].tap()
        app.buttons["style.highlight.custom"].tap()
        let apply = app.buttons["colorSheet.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5))

        let custom = app.buttons["style.highlight.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        XCTAssertTrue(custom.isSelected, "the color the sheet showed is the block's background")
        XCTAssertFalse(app.buttons["style.highlight.none"].isSelected)
    }

    func testTheStripNeverTakesOverAVoiceTake() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.voice"].waitForExistence(timeout: 5))
        app.buttons["mode.voice"].tap()
        app.buttons["recorder.record"].tap()
        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 5))

        tapText("caption")
        app.buttons["style.mic"].tap()
        // Give a wrongly started transcription time to land.
        let dictated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "Transcribed"), object: field
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dictated], timeout: 3), .timedOut,
                       "the voice take is not dictated into the block")
        XCTAssertEqual(field.value as? String, "caption")

        app.buttons["keyboard.done"].tap()
        let stop = app.buttons["recorder.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        XCTAssertTrue(app.buttons["recorder.keep"].waitForExistence(timeout: 5), "Stop still ends the take")
    }
}
