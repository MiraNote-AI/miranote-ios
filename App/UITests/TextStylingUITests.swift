import XCTest

/// Text styling while editing (redesign phase B1): font, alignment, color and
/// text background from the keyboard accessory, each one undo step.
final class TextStylingUITests: XCTestCase {
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

    private func startEditingText(_ words: String) {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
    }

    func testStylingRowsApplyAndShowTheCurrentStyle() {
        startEditingText("sunny afternoon")

        // Font row: picking a face marks nothing broken and returns cleanly.
        app.buttons["style.sizes"].tap()
        let futura = app.buttons["style.font.Futura"]
        XCTAssertTrue(futura.waitForExistence(timeout: 5))
        futura.tap()
        app.buttons["Back"].tap()

        // Alignment steps leading -> center -> trailing.
        let align = app.buttons["style.align"]
        XCTAssertEqual(align.value as? String, "leading")
        align.tap()
        XCTAssertEqual(align.value as? String, "center")

        // Color: the picked swatch reads as selected.
        app.buttons["style.colors"].tap()
        let green = app.buttons["style.color.#24382D"]
        XCTAssertTrue(green.waitForExistence(timeout: 5))
        green.tap()
        XCTAssertTrue(green.isSelected)
        app.buttons["Back"].tap()

        // Text background: on, then off again.
        app.buttons["style.highlight"].tap()
        let cream = app.buttons["style.highlight.#FFFDF8"]
        XCTAssertTrue(cream.waitForExistence(timeout: 5))
        cream.tap()
        XCTAssertTrue(cream.isSelected)
        app.buttons["style.highlight.none"].tap()
        XCTAssertFalse(cream.isSelected)
        app.buttons["Back"].tap()

        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.staticTexts["sunny afternoon"].waitForExistence(timeout: 5))
    }

    func testAlignmentIsUndoable() {
        startEditingText("undo me")
        let align = app.buttons["style.align"]
        align.tap()
        XCTAssertEqual(align.value as? String, "center")
        app.buttons["keyboard.done"].tap()

        app.buttons["editor.undo"].tap()
        let block = app.staticTexts["undo me"]
        XCTAssertTrue(block.waitForExistence(timeout: 5), "undoing the style keeps the words")
        block.tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        if !field.exists { block.tap() }
        XCTAssertTrue(app.buttons["style.align"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["style.align"].value as? String, "leading", "back to leading")
    }
}
