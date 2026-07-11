import XCTest

/// Editing a placed sticker: the Mira ask and the long-press panel
/// (deterministic under -UITEST: the mock studio answers instantly).
final class StickerEditUITests: XCTestCase {
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

    /// Draw-and-place one sticker, then wait out the placement receipt
    /// so the next step starts from a quiet strip.
    private func placeOneSticker() {
        ask("draw a sticker of a coffee cup")
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 5))
        let receipt = app.staticTexts["mira.receipt"]
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: receipt)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 12), .completed,
                       "the placement receipt clears")
    }

    func testAskRestylesThePlacedSticker() {
        startMemory()
        placeOneSticker()

        ask("make the sticker blue")
        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 8),
                      "the edit lands with a receipt")
        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        XCTAssertTrue(sticker.exists, "the element is still a sticker")
    }

    func testLongPressPanelEditsTheSticker() {
        startMemory()
        placeOneSticker()

        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        sticker.press(forDuration: 1.1)
        let entry = app.buttons["Edit sticker"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "the menu gains Edit sticker")
        entry.tap()

        let field = app.textFields["sticker.ai.instruction"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("make it blue")
        app.buttons["sticker.ai.run"].tap()
        XCTAssertTrue(
            app.staticTexts["Done -- take a look. Undo brings the old one back."]
                .waitForExistence(timeout: 8),
            "the panel reports the swap"
        )
    }
}
