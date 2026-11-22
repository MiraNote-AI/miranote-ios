import XCTest

/// The blocks' own menu while writing (#236): the block being written has
/// the system's edit menu only.
final class TextBlockMenuUITests: TextToolUITestCase {
    private var field: XCUIElement { any("canvas.textEditor") }

    /// A long press in the block being written shows the system's edit
    /// menu only -- its own menu used to come with Paste and stay over the
    /// chat box -- and another block keeps its menu meanwhile.
    func testALongPressInTheBlockBeingWrittenShowsOnlyTheEditMenu() {
        write("first block")
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("we walked")
        let writing = canvasState()["writing"] as? String ?? ""
        app.paste(" far", into: field)
        XCTAssertTrue(waitForField("CONTAINS", "far"), "pasted: \(fieldValue())")
        XCTAssertFalse(app.buttons["Edit text"].exists, "no block menu came with the edit menu")
        XCTAssertFalse(app.buttons["Duplicate"].exists, "no block menu came with the edit menu")
        XCTAssertEqual(canvasState()["writing"] as? String, writing, "still writing the block")

        app.staticTexts["first block"].press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Edit text"].waitForExistence(timeout: 3), "another block keeps its menu")
    }


}
}
