import UIKit
import XCTest

/// Asking Mira from the canvas (handoff screen 06): the composer opens the
/// Mira canvas chat, the question is typed in its box at the bottom, and
/// Return (the keyboard's Go) sends it.
extension XCUIApplication {
    /// The composer at rest; its label is the waiting draft, or the
    /// placeholder.
    var miraComposer: XCUIElement { buttons["mira.composer"] }

    /// The chat's question field (one line; Return sends).
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

    /// A tap on the empty page below a block lets go of the selection. With
    /// a text block selected the composer refines it in place (F6B); with
    /// nothing selected it opens the chat: the way there from a selected
    /// block, as after Back from writing one.
    func letGoOfTheSelection() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
    }

    func openMiraChat(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(miraComposer.waitForExistence(timeout: 5), "the composer is up", file: file, line: line)
        miraComposer.tap()
        XCTAssertTrue(miraInput.waitForExistence(timeout: 5), "the chat opens", file: file, line: line)
    }

    /// Home's ask bar, a button: one tap opens the Mira chat.
    var homeAsk: XCUIElement { buttons["home.ask"] }

    /// The Mira chat's field (a text view; Return sends).
    var chatField: XCUIElement { descendants(matching: .any)["chat.field"] }

    /// Opens the Mira chat from Home's ask bar and sends `words` from its
    /// field, which has the keyboard without a tap.
    func askFromHome(_ words: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(homeAsk.waitForExistence(timeout: 8), "Home's ask bar is up", file: file, line: line)
        homeAsk.tap()
        XCTAssertTrue(chatField.waitForExistence(timeout: 5), "the chat opens", file: file, line: line)
        chatField.typeText(words)
        buttons["chat.send"].tap()
    }

    func askMira(_ words: String, file: StaticString = #filePath, line: UInt = #line) {
        openMiraChat(file: file, line: line)
        miraInput.tap()
        miraInput.typeText(words + "\n")
    }
}
