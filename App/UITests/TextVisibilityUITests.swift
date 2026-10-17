import XCTest

/// Owner, TestFlight 1.0(5): the text tools over the keyboard (the row,
/// the tool bar, the dictation strip) covered the block being written. A
/// block near the page bottom -- new, or opened again -- sits fully between
/// the header and the text tools while it is written.
final class TextVisibilityUITests: XCTestCase {
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

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private var field: XCUIElement { any("canvas.textEditor") }

    /// Three photos, so the next block lands near the page bottom.
    private func fillThePage() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        app.buttons["image.library.open"].tap()
        XCTAssertTrue(any("image.library.photo.0").waitForExistence(timeout: 5))
        for index in 0..<3 { any("image.library.photo.\(index)").tap() }
        app.buttons["image.composer.add"].tap()
        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    /// The block's frame lies below the header and above every text tool.
    private func assertClearOfTheTools(_ when: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["style.sizes"].waitForExistence(timeout: 5))
        // The scroll into view animates.
        Thread.sleep(forTimeInterval: 1)
        let tools = app.buttons.matching(NSPredicate(
            format: "identifier == 'style.sizes' OR identifier BEGINSWITH 'style.font.' OR identifier BEGINSWITH 'style.size.'"
        )).allElementsBoundByIndex.map(\.frame.minY) + [any("style.mic").frame.minY]
        let toolsTop = tools.min() ?? 0
        let headerBottom = app.buttons["keyboard.done"].frame.maxY
        XCTAssertLessThanOrEqual(field.frame.maxY, toolsTop + 0.5,
                                 "\(when): the block (\(field.frame)) runs under the text tools (top \(toolsTop))")
        XCTAssertGreaterThanOrEqual(field.frame.minY, headerBottom - 0.5,
                                    "\(when): the block (\(field.frame)) runs under the header (\(headerBottom))")
    }

    func testTheBlockBeingWrittenStaysAboveTheTextTools() {
        fillThePage()
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lunch by the river")
        assertClearOfTheTools("a new block")
        field.typeText(", then a long walk home with Sam and Jo under the golden light")
        assertClearOfTheTools("the block grown by typing")

        app.buttons["keyboard.done"].tap()
        let block = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'lunch by the river'")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        block.tap()
        if !field.exists { block.tap() }
        assertClearOfTheTools("the block opened again")
    }
}
