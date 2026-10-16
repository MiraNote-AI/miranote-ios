import UIKit
import XCTest

/// Asking Mira from the canvas (handoff screen 06): the composer opens the
/// Mira canvas chat, the question is typed in its dark capsule, and Return
/// (the keyboard's Go) sends it.
extension XCUIApplication {
    /// The composer at rest; its label is the waiting draft, or the
    /// placeholder.
    var miraComposer: XCUIElement { buttons["mira.composer"] }

    /// The chat's question field (single line; Return sends).
    var miraInput: XCUIElement { descendants(matching: .any)["mira.input"].firstMatch }

    /// Pastes `text` into `field` through the system edit menu, as a person
    /// pastes (the pasteboard is shared with the simulator's apps).
    func paste(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        UIPasteboard.general.string = text
        field.press(forDuration: 1.2)
        // A menu item or a button, depending on the iOS edit menu.
        let item = descendants(matching: .any).matching(NSPredicate(
            format: "label == 'Paste' AND (elementType == %d OR elementType == %d)",
            XCUIElement.ElementType.menuItem.rawValue, XCUIElement.ElementType.button.rawValue
        )).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the edit menu offers Paste", file: file, line: line)
        item.tap()
    }

    func openMiraChat(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(miraComposer.waitForExistence(timeout: 5), "the composer is up", file: file, line: line)
        miraComposer.tap()
        XCTAssertTrue(miraInput.waitForExistence(timeout: 5), "the chat opens", file: file, line: line)
    }

    func askMira(_ words: String, file: StaticString = #filePath, line: UInt = #line) {
        openMiraChat(file: file, line: line)
        miraInput.tap()
        miraInput.typeText(words + "\n")
    }
}
