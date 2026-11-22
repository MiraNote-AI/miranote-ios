import XCTest

/// VoiceOver's two-finger escape while writing (#236, after #223 and
/// #225), as the Background slot's (#226): on a tool's row it goes back up
/// to the text row, as the row's Back does; on the text row and the chat
/// box's mic it ends the writing, as the text row's Back does. Through the
/// -UITEST escape probe (`voiceOverEscape(from:)`), a model of VoiceOver's
/// walk.
final class TextEscapeUITests: TextToolUITestCase {
    private var field: XCUIElement { any("canvas.textEditor") }

    private func startWriting(_ words: String) -> String {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
        let writing = canvasState()["writing"] as? String ?? ""
        XCTAssertFalse(writing.isEmpty)
        return writing
    }

    private func assertTheWritingEnded(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5), message, file: file, line: line)
        XCTAssertEqual(canvasState()["writing"] as? String, "", message, file: file, line: line)
    }

    func testEscapeOnAToolRowGoesBackUpToTheTextRow() {
        let writing = startWriting("we walked")
        let rows = [("style.font", "text.row.font", "style.font.Josefin"),
                    ("style.size", "text.row.size", "style.size.M"),
                    ("style.colors", "text.row.color", "style.color.custom"),
                    ("style.ai", "text.row.ai", "style.ai.original"),
                    ("style.highlight", "text.row.background", "style.highlight.none")]
        for (tool, row, cell) in rows {
            app.openTextRow(tool)
            XCTAssertTrue(any(row).waitForExistence(timeout: 3), "\(row) shows")
            let record = app.voiceOverEscape(from: cell)
            XCTAssertTrue(record.contains("taken"), "\(row): the escape was taken: \(record)")
            XCTAssertTrue(app.buttons["keyboard.done"].waitForExistence(timeout: 3),
                          "\(row): escape goes back up to the text row")
            XCTAssertTrue(any("text.row.tools").exists, "\(row): the text row is back in the slot")
            XCTAssertEqual(canvasState()["writing"] as? String, writing, "\(row): still writing the same block")
        }
        // From the row's own Back as from its cells.
        app.openTextRow("style.size")
        app.voiceOverEscape(from: "text.row.back")
        XCTAssertTrue(app.buttons["keyboard.done"].waitForExistence(timeout: 3), "the row's Back: up one level")
        XCTAssertEqual(canvasState()["writing"] as? String, writing)
        XCTAssertTrue(field.exists, "the block is still being written")
    }

    func testEscapeOnTheTextRowEndsTheWriting() {
        _ = startWriting("we walked")
        let record = app.voiceOverEscape(from: "style.font")
        XCTAssertTrue(record.contains("taken"), "the escape was taken: \(record)")
        assertTheWritingEnded("on the text row, escape ends the writing, as its Back does")
        XCTAssertTrue(app.staticTexts["we walked"].exists, "the words stay on the page")
    }

    func testEscapeOnTheChatBoxMicEndsTheWriting() {
        _ = startWriting("we walked")
        let record = app.voiceOverEscape(from: "style.mic")
        XCTAssertTrue(record.contains("taken"), "the escape was taken: \(record)")
        assertTheWritingEnded("escape on the chat box's mic ends the writing")
    }


}
}
