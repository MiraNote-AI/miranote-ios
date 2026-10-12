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
        // On a default page there is nothing to clear, and the receipt says
        // so rather than claiming a change it cannot revert (#87).
        ask("remove the background")
        XCTAssertTrue(
            app.staticTexts["The page is already on its default background."].waitForExistence(timeout: 8))

        app.buttons["mode.background"].tap()
        let lilac = app.buttons["background.color.#E5D9F0"]
        XCTAssertTrue(lilac.waitForExistence(timeout: 5))
        lilac.tap()
        app.buttons["mode.background"].tap()

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

    // The handoff's "Change background" quick action (screen 06): offered once
    // the page has something on it, it runs a normal background turn, and it
    // leaves once the page has a background of its own.
    func testChangeBackgroundQuickActionRunsAndLeaves() {
        startMemory()
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lunch by the river")
        app.buttons["keyboard.done"].tap()

        let chip = app.buttons["mira.suggestion.Change the background"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "the chip ran a background turn")
        first.tap()
        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 5))

        XCTAssertFalse(
            app.buttons["mira.suggestion.Change the background"].waitForExistence(timeout: 3),
            "a page with its own background is not offered another"
        )
    }

    // Paper and page color apply in place; Default returns to the gradient
    // but keeps the paper.
    func testPaperAndPageColorApplyAndDefaultResetsColor() {
        startMemory()
        app.buttons["mode.background"].tap()
        let grid = app.buttons["background.paper.grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["background.paper.blank"].isSelected, "new pages start blank")
        grid.tap()
        XCTAssertTrue(grid.isSelected)
        let gridShot = XCTAttachment(screenshot: app.screenshot())
        gridShot.name = "grid paper"
        gridShot.lifetime = .keepAlways
        add(gridShot)

        let lilac = app.buttons["background.color.#E5D9F0"]
        lilac.tap()
        XCTAssertTrue(lilac.isSelected)
        XCTAssertFalse(app.buttons["background.default"].isSelected)

        app.buttons["background.default"].tap()
        XCTAssertTrue(app.buttons["background.default"].isSelected)
        XCTAssertFalse(lilac.isSelected)
        XCTAssertTrue(grid.isSelected, "Default resets the color, not the paper")
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

        // The panel stays open (paper and color sit beside Default).
        XCTAssertTrue(defaultChip.isSelected, "back on the default backdrop")
    }
}
