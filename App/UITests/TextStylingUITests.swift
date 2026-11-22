import XCTest

/// Text styling while editing (redesign phase B1, handoff screens 11-18):
/// font, alignment, color and text background from the text tool bar, each
/// one undo step.
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

        // Font row (Aa): the picked face reads as selected.
        app.openTextRow("style.font")
        let futura = app.buttons["style.font.Futura"]
        XCTAssertTrue(futura.waitForExistence(timeout: 5))
        futura.tap()
        XCTAssertTrue(futura.isSelected)

        // Size row: the picked size reads as selected.
        app.openTextRow("style.size")
        let large = app.buttons["style.size.L"]
        XCTAssertTrue(large.waitForExistence(timeout: 5))
        large.tap()
        XCTAssertTrue(large.isSelected)

        // Alignment, on the text row, steps leading -> center -> trailing.
        app.backToTextRow()
        let align = app.buttons["style.align"]
        XCTAssertEqual(align.value as? String, "Left")
        align.tap()
        XCTAssertEqual(align.value as? String, "Centered")

        // Color: the picked swatch reads as selected.
        app.openTextRow("style.colors")
        let green = app.buttons["style.color.#24382D"]
        XCTAssertTrue(green.waitForExistence(timeout: 5))
        green.tap()
        XCTAssertTrue(green.isSelected)

        // Text background: on, then off again.
        app.openTextRow("style.highlight")
        let highlight = app.buttons["style.highlight.#B4826D"]
        XCTAssertTrue(highlight.waitForExistence(timeout: 5))
        highlight.tap()
        XCTAssertTrue(highlight.isSelected)
        app.buttons["style.highlight.none"].tap()
        XCTAssertFalse(highlight.isSelected)

        app.backToTextRow()
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.staticTexts["sunny afternoon"].waitForExistence(timeout: 5))
    }

    func testAlignmentIsUndoable() {
        startEditingText("undo me")
        let align = app.buttons["style.align"]
        align.tap()
        XCTAssertEqual(align.value as? String, "Centered")
        app.buttons["keyboard.done"].tap()

        app.buttons["editor.undo"].tap()
        let block = app.staticTexts["undo me"]
        XCTAssertTrue(block.waitForExistence(timeout: 5), "undoing the style keeps the words")
        block.tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        if !field.exists { block.tap() }
        XCTAssertTrue(app.buttons["style.align"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["style.align"].value as? String, "Left", "back to leading")
    }
}
