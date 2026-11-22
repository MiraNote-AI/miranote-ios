import XCTest

/// The blocks' own menu while writing (#236): the block being written has
/// the system's edit menu only, and "Edit text" on another block switches
/// the writing to it -- from the caret in the block as from the caret in
/// the chat box.
final class TextBlockMenuUITests: TextToolUITestCase {
    private var field: XCUIElement { any("canvas.textEditor") }
    private var ask: XCUIElement { app.descendants(matching: .any)["writing.ask"] }

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

    /// "Edit text" on another block switches the writing to it, the
    /// keyboard up and the caret in it -- from the caret in the block (the
    /// writing used to end there) as from the caret in the chat box.
    func testEditTextOnAnotherBlockSwitchesTheWritingFromTheBlock() {
        assertEditTextSwitchesTheWriting(fromChatBox: false)
    }

    func testEditTextOnAnotherBlockSwitchesTheWritingFromTheChatBox() {
        assertEditTextSwitchesTheWriting(fromChatBox: true)
    }

    private func assertEditTextSwitchesTheWriting(fromChatBox: Bool, file: StaticString = #filePath,
                                                  line: UInt = #line) {
        write("first block")
        write("second block")
        editText("first block")
        let first = canvasState()["writing"] as? String ?? ""
        if fromChatBox { ask.tap() }
        XCTAssertTrue(waitForCaret(in: fromChatBox ? ask : field), "the caret is where it starts",
                      file: file, line: line)

        editText("second block")
        let writing = canvasState()["writing"] as? String ?? ""
        XCTAssertFalse(writing.isEmpty, "still writing", file: file, line: line)
        XCTAssertNotEqual(writing, first, "writing the second block", file: file, line: line)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard is up", file: file, line: line)
        XCTAssertTrue(waitForCaret(in: field), "the caret is in the second block", file: file, line: line)
        app.typeText("!")
        XCTAssertTrue(waitForField("==", "second block!"), "typed into it: \(fieldValue())", file: file, line: line)
    }
}
