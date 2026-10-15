import XCTest

/// The Sticker panel (Oct 3 decision, handoff screen 30): Make is the first
/// tab and stays clean, Favorites is the second, and the prompt lives in the
/// fixed bottom composer.
final class StickerTabsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.sticker"].waitForExistence(timeout: 5))
        app.buttons["mode.sticker"].tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testMakeIsFirstAndCleanFavoritesIsSecond() {
        let make = app.buttons["sticker.tab.make"]
        let favorites = app.buttons["sticker.tab.favorites"]
        XCTAssertTrue(make.waitForExistence(timeout: 5))
        XCTAssertTrue(make.isSelected, "the panel opens on Make")
        XCTAssertTrue(app.staticTexts["Describe a sticker below -- Mira makes a couple to pick from."].exists,
                      "Make opens on its own prompt")
        let placeable = NSPredicate(format: "identifier BEGINSWITH 'library.item.' OR identifier BEGINSWITH 'sticker.preset.'")
        XCTAssertEqual(app.buttons.matching(placeable).count, 0, "no favorites or presets on Make")
        XCTAssertFalse(app.buttons["sticker.generate.run"].isEnabled, "Generate waits for words")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "sticker panel"
        shot.lifetime = .keepAlways
        add(shot)

        favorites.tap()
        XCTAssertTrue(favorites.isSelected)
        XCTAssertFalse(make.isSelected)
    }

    func testGeneratingFromFavoritesShowsTheResultsOnMake() {
        app.buttons["sticker.tab.favorites"].tap()
        let prompt = app.textFields["sticker.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("a coffee cup")
        app.buttons["sticker.generate.run"].tap()

        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sticker.result.0").firstMatch
            .waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["sticker.tab.make"].isSelected, "results show where they are made")
    }
}
