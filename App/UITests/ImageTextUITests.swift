import XCTest

/// Words-about-pictures and pictures-from-words (mock studio).
final class ImageTextUITests: XCTestCase {
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
        let input = app.textFields["mira.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(words)
        app.buttons["mira.go"].tap()
    }

    private func addSamplePhoto() {
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        let second = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
            .withOffset(CGVector(dx: 0, dy: 120)).tap()
    }

    func testDescribeAskAddsWordsNotARestyle() {
        startMemory()
        addSamplePhoto()
        ask("Add a text to describe the picture")
        XCTAssertTrue(app.staticTexts["Added a few words."].waitForExistence(timeout: 8),
                      "the caption receipt, not a restyle")
    }

    func testTextIntoPictureLandsAnImage() {
        startMemory()
        app.buttons["mode.text"].tap()
        // Multiline SwiftUI TextFields surface as text views, so match the
        // identifier across any element type (CanvasEditorUITests pattern).
        let editorField = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(editorField.waitForExistence(timeout: 5))
        editorField.typeText("a quiet morning by the sea")
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        ask("turn this text into a picture")

        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "element.image").firstMatch.exists,
            "the illustration landed")
    }
}
