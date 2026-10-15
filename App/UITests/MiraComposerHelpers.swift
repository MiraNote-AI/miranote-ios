import XCTest

/// Asking Mira from the canvas (handoff screen 06): the composer opens the
/// Mira canvas chat, the question is typed in its dark capsule, and Return
/// (the keyboard's Go) sends it.
extension XCUIApplication {
    /// The composer at rest; its label is the waiting draft, or the
    /// placeholder.
    var miraComposer: XCUIElement { buttons["mira.composer"] }

    /// The chat's question field (a multi-line field: a text view).
    var miraInput: XCUIElement { descendants(matching: .any)["mira.input"].firstMatch }

    func openMiraChat(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(miraComposer.waitForExistence(timeout: 5), "the composer is up", file: file, line: line)
        miraComposer.tap()
        XCTAssertTrue(miraInput.waitForExistence(timeout: 5), "the chat opens", file: file, line: line)
    }

    func askMira(_ words: String, file: StaticString = #filePath, line: UInt = #line) {
        openMiraChat(file: file, line: line)
        miraInput.tap()
        miraInput.typeText(words)
        // Return as its own key press, as a person types it (a phrase that
        // arrives with its new line in one change reads as a paste).
        miraInput.typeText("\n")
    }
}
