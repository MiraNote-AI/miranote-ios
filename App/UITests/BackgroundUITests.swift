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

    // The Background tool's moods are Mira background asks: one tap runs the
    // same turn as typing it, candidates and all.
    func testBackgroundToolMoodRunsMiraAsk() {
        startMemory()
        app.buttons["mode.background"].tap()
        XCTAssertTrue(app.buttons["background.default"].waitForExistence(timeout: 5))
        app.buttons["background.mood.Sunset glow"].tap()

        XCTAssertFalse(app.buttons["background.default"].exists, "the panel closes for the turn")
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "the mood came back as background candidates")
        first.tap()
        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 5))
    }

    // Default restores the built-in backdrop after a painted one.
    func testBackgroundToolDefaultClearsPaintedBackdrop() {
        startMemory()
        ask("give this page a sunset background")
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 5))

        app.buttons["mode.background"].tap()
        let defaultChip = app.buttons["background.default"]
        XCTAssertTrue(defaultChip.waitForExistence(timeout: 5))
        XCTAssertFalse(defaultChip.isSelected, "a painted page is not on the default")
        defaultChip.tap()

        app.buttons["mode.background"].tap()
        XCTAssertTrue(app.buttons["background.default"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["background.default"].isSelected, "back on the default backdrop")
    }
}
