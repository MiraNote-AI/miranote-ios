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

    // The live mic says "Listening...", and the transcript lands in the
    // block being edited (deterministic mocks under -UITEST).
    func testDictationListensAndAppendsTranscript() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("note")

        app.buttons["style.mic"].tap()
        XCTAssertTrue(
            app.staticTexts["Listening..."].waitForExistence(timeout: 5),
            "a live mic reads as active, not as an error badge"
        )

        app.buttons["style.mic"].tap()
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
