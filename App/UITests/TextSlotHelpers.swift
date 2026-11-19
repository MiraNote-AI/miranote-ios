import XCTest

/// The text slot while writing (#205): one row at a time. A tool in the
/// text row opens its row in the text row's place; `text.row.back` goes
/// back up one level, and only the text row's Back (`keyboard.done`) ends
/// the writing.
extension XCUIApplication {
    /// Opens a tool's row (`style.font`, `style.size`, `style.colors`,
    /// `style.ai`, `style.highlight`) from either level.
    func openTextRow(_ tool: String, file: StaticString = #filePath, line: UInt = #line) {
        backToTextRow(file: file, line: line)
        XCTAssertTrue(buttons[tool].waitForExistence(timeout: 5), "\(tool) is in the text row", file: file, line: line)
        buttons[tool].tap()
        XCTAssertTrue(buttons["text.row.back"].waitForExistence(timeout: 5), "\(tool) opened its row",
                      file: file, line: line)
    }

    /// Up to the text row if a tool's row is showing.
    func backToTextRow(file: StaticString = #filePath, line: UInt = #line) {
        let back = buttons["text.row.back"]
        guard back.exists else { return }
        back.tap()
        XCTAssertTrue(buttons["keyboard.done"].waitForExistence(timeout: 5), "back on the text row",
                      file: file, line: line)
    }

    /// The rows in the text slot now: one, except mid level change.
    var textSlotRows: XCUIElementQuery {
        descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'text.row.' AND identifier != 'text.row.back'"
        ))
    }
}
