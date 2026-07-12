import XCTest

/// UI tests for canvas text display rendering (light markdown). Split
/// from CanvasEditorUITests for size.
final class TextRenderingUITests: XCTestCase {
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

    // List lines display as real bullets on the canvas, not raw "- "
    // markers -- while editing hands back the raw characters (issue #28 F4).
    func testTextBlockRendersListMarkersAsBullets() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()

        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("groceries\n- eggs\n- milk")

        app.buttons["keyboard.done"].tap()
        let block = app.staticTexts["groceries\n\u{2022}  eggs\n\u{2022}  milk"]
        XCTAssertTrue(block.waitForExistence(timeout: 5), "display shows bullets")

        // Re-entering the block edits the raw markers, not the glyphs
        // (first tap selects, second starts editing). App-anchored
        // coordinates: the staticText disappears once editing starts, so
        // element-anchored taps would re-query and fail.
        let frame = block.frame
        let center = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        center.tap()
        center.tap()
        let editor = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "groceries\n- eggs\n- milk")
    }
}
