import XCTest

/// TestFlight 1.0(14): "tapping the chat box flies to the Mira chat". After
/// Back the written block stays selected (screen 21) and the bottom
/// composer reads "Ask Mira to refine...", the words of the chat box over
/// the keyboard while writing. With one text block selected its tap now
/// does what they say: the block's writing opens again with the caret in
/// the chat box, where Go rewrites the block (F6B). Anything else still
/// opens the Mira chat (P2). Under -UITEST the rewrite is the mock's
/// `/rewrite` answer, "(rewritten -- mock)".
final class TextComposerRefineUITests: TextToolUITestCase {
    private var field: XCUIElement { any("canvas.textEditor") }
    private var ask: XCUIElement { app.descendants(matching: .any)["writing.ask"] }
    private var go: XCUIElement { app.buttons["writing.go"] }

    /// Write a block, Back, tap the composer: the same block is written
    /// again, keyboard up, the caret in the chat box, and the Mira chat
    /// never opens. An ask and Go rewrite the block, and the writing goes
    /// on with the caret back in the block.
    func testAComposerTapWithTheWrittenBlockSelectedRefinesItInPlace() {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("we walked")
        let block = canvasState()["writing"] as? String ?? ""
        XCTAssertFalse(block.isEmpty)
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "Back ended the writing")
        XCTAssertEqual(canvasState()["selected"] as? String, block, "the block stays selected")
        XCTAssertEqual(app.miraComposer.label, "Ask Mira to refine...")

        app.miraComposer.tap()
        XCTAssertTrue(waitForCaret(in: ask), "the caret is in the chat box")
        XCTAssertFalse(app.miraInput.waitForExistence(timeout: 1), "the Mira chat never opens")
        XCTAssertEqual(canvasState()["writing"] as? String, block, "the same block is being written")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "the keyboard is up")
        XCTAssertTrue(field.exists, "the block has its editor (dashed frame)")

        ask.typeText("make it warmer")
        go.tap()
        XCTAssertTrue(waitForField("==", "(rewritten -- mock) we walked"), "Go rewrote the block: \(fieldValue())")
        XCTAssertEqual(canvasState()["writing"] as? String, block, "still writing the same block")
        app.typeText("!")
        XCTAssertTrue(waitForField("==", "(rewritten -- mock) we walked!"),
                      "the caret is back in the block: \(fieldValue())")
        XCTAssertFalse(app.miraInput.exists, "the Mira chat never opened")
    }

    /// The composer still opens the Mira chat whenever its words are not
    /// the chat box's: with the block let go of (a page tap, the way to the
    /// chat from a selected block), and, once it is selected again, with a
    /// draft from the chat waiting and with a result waiting.
    func testTheComposerStillOpensTheChatWhenItIsNotTheChatBox() {
        write("we walked")
        let block = canvasState()["selected"] as? String ?? ""
        XCTAssertFalse(block.isEmpty, "Back left the block selected")
        app.letGoOfTheSelection()
        XCTAssertEqual(canvasState()["selected"] as? String, "", "a page tap lets go of it")
        XCTAssertEqual(app.miraComposer.label, "Ask Mira anything")
        app.openMiraChat()
        XCTAssertEqual(canvasState()["writing"] as? String, "", "nothing is written")
        app.miraInput.typeText("polish the text")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.miraInput.waitForNonExistence(timeout: 5), "Done closes the chat")

        app.staticTexts["we walked"].tap()
        XCTAssertEqual(canvasState()["selected"] as? String, block, "the block is selected again")
        XCTAssertEqual(app.miraComposer.label, "polish the text", "the draft waits")
        app.openMiraChat()
        XCTAssertEqual(app.miraInput.value as? String, "polish the text", "the chat opens on the draft")
        XCTAssertEqual(canvasState()["writing"] as? String, "")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.miraInput.waitForNonExistence(timeout: 5))

        app.buttons["mira.go"].tap()
        XCTAssertTrue(app.buttons["mira.keep"].waitForExistence(timeout: 8), "the result waits")
        XCTAssertEqual(canvasState()["selected"] as? String, block, "with the block selected")
        XCTAssertEqual(app.miraComposer.label, "Ask Mira to refine...")
        app.openMiraChat()
        XCTAssertEqual(canvasState()["writing"] as? String, "")
    }
}
