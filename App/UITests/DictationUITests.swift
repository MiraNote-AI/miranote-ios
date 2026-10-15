import XCTest

/// Dictation in the text accessory: split from CanvasEditorUITests for
/// size (the shared 250-line type cap).
final class DictationUITests: XCTestCase {
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

    // Hold to talk (the Mira Dictation strip, screens 11-18): pressing
    // starts the mic, letting go ends the take and the words land.
    func testHoldingTheStripDictates() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("held")

        app.buttons["style.mic"].press(forDuration: 1.5)
        let appended = NSPredicate(format: "value CONTAINS %@", "Transcribed voice note (mock)")
        expectation(for: appended, evaluatedWith: field)
        waitForExpectations(timeout: 5)
        XCTAssertNotEqual(app.buttons["style.mic"].value as? String, "Listening...", "letting go ended the take")
    }

    // A tap leaves the mic listening ("Listening..."), a second tap ends
    // the take, and the transcript lands in the block being edited
    // (deterministic mocks under -UITEST).
    func testDictationListensAndAppendsTranscript() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("note")

        // The strip's subtitle reads "Listening..." -- its accessibility
        // value carries the same words.
        let mic = app.buttons["style.mic"]
        mic.tap()
        expectation(for: NSPredicate(format: "value == %@", "Listening..."), evaluatedWith: mic)
        waitForExpectations(timeout: 5)

        mic.tap()
        let appended = NSPredicate(format: "value CONTAINS %@", "Transcribed voice note (mock)")
        expectation(for: appended, evaluatedWith: field)
        waitForExpectations(timeout: 5)

        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(
            app.staticTexts["note Transcribed voice note (mock)"].waitForExistence(timeout: 5),
            "the transcript joined the words already in the block"
        )
    }
}
