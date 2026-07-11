import XCTest

/// Page background asks (deterministic under -UITEST).
final class BackgroundUITests: XCTestCase {
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

    func testBackgroundAskPlacesViaChoices() {
        startMemory()
        ask("give this page a sunset background")
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "two candidates arrive")
        first.tap()
        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 5))
    }

    func testClearBackgroundReceipts() {
        startMemory()
        ask("remove the background")
        XCTAssertTrue(app.staticTexts["Cleared the background."].waitForExistence(timeout: 8))
    }
}
