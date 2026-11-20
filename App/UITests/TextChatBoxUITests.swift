import XCTest

/// #205 PR 3, the chat box while writing: its trailing button is the mic
/// while it is empty and Go once there are words (F7A); the caret moves
/// there and back without ending the writing; Go has Mira rewrite the
/// block, previewed in place on the Polish row with no chip selected (F6B,
/// H3A). Under -UITEST the rewrite is the mock's `/rewrite` answer,
/// "(rewritten -- mock)", distinct from every Polish chip's.
final class TextChatBoxUITests: TextToolUITestCase {
    private var field: XCUIElement { any("canvas.textEditor") }
    private var ask: XCUIElement { app.descendants(matching: .any)["writing.ask"] }
    private var go: XCUIElement { app.buttons["writing.go"] }
    private var mic: XCUIElement { any("style.mic") }

    private func fieldValue() -> String { field.value as? String ?? "" }

    private func waitForField(_ predicate: String, _ words: String, timeout: TimeInterval = 5) -> Bool {
        let reads = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value \(predicate) %@", words),
                                              object: field)
        return XCTWaiter().wait(for: [reads], timeout: timeout) == .completed
    }

    func testTheMicGivesWayToGoOnceThereAreWords() {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("we walked")
        XCTAssertTrue(mic.waitForExistence(timeout: 3), "empty: the mic")
        XCTAssertFalse(go.exists)

        ask.tap()
        ask.typeText("warm")
        XCTAssertTrue(go.waitForExistence(timeout: 3), "words: Go")
        XCTAssertFalse(mic.exists, "Go takes the mic's place")

        ask.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        XCTAssertTrue(mic.waitForExistence(timeout: 3), "empty again: the mic is back")
        XCTAssertFalse(go.exists)
    }

    /// The caret moving from the block to the chat box is still the same
    /// writing: no text exit, no second keep-clear scroll, no second rise
    /// of the tools (a new open would count one).
    func testMovingTheCaretToTheChatBoxKeepsTheWriting() throws {
        // A full page: the new block lands low and scrolls clear once.
        write("first line of the day")
        write("second, a little longer than the first one")
        write("third")
        try openText()
        sleep(1)
        let before = textOpen(after: 4)
        XCTAssertEqual(before["clearScrolls"] as? Int, 1, "\(before)")
        let writing = canvasState()["writing"] as? String ?? ""
        XCTAssertFalse(writing.isEmpty)
        field.typeText("fourth")

        ask.tap()
        ask.typeText("make it warmer")
        sleep(1)

        let state = canvasState()
        XCTAssertEqual(state["writing"] as? String, writing, "still writing the same block")
        let after = state["textOpen"] as? [String: Any] ?? [:]
        XCTAssertEqual(after["opens"] as? Int, 4, "no new text open: \(after)")
        XCTAssertEqual(after["clearScrolls"] as? Int, 1, "the block is not scrolled again: \(after)")
        XCTAssertEqual(after["lightRises"] as? Int, 0, "the keyboard stays dark: \(after)")
        XCTAssertEqual(state["textToolsShown"] as? Bool, true)
        XCTAssertTrue(app.buttons["keyboard.done"].isHittable, "the text row stays")
        XCTAssertTrue(field.exists, "the block keeps its editor (dashed frame)")
        XCTAssertEqual(ask.value as? String, "make it warmer", "the words went to the chat box")
        XCTAssertEqual(fieldValue(), "fourth", "and not to the block")
    }

    func testGoPreviewsTheRewriteInPlaceWithNoChipSelected() {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("we walked")
        let writing = canvasState()["writing"] as? String ?? ""
        XCTAssertFalse(writing.isEmpty)
        ask.tap()
        ask.typeText("make it warmer")
        go.tap()

        XCTAssertTrue(waitForField("==", "(rewritten -- mock) we walked"),
                      "the block shows the rewrite: \(fieldValue())")
        let original = app.buttons["style.ai.original"]
        XCTAssertTrue(original.waitForExistence(timeout: 3), "the Polish row shows")
        for choice in ["original", "clean", "expand"] {
            XCTAssertFalse(app.buttons["style.ai.\(choice)"].isSelected, "no chip is selected (\(choice))")
        }
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'style.ai.'")).count, 3,
                       "no extra chip")
        XCTAssertTrue(mic.waitForExistence(timeout: 3), "the box is empty again: the mic")
        XCTAssertEqual(ask.value as? String ?? "", ask.placeholderValue ?? "", "the words left the box")

        // The caret is back at the end of the block.
        app.typeText("!")
        XCTAssertTrue(waitForField("==", "(rewritten -- mock) we walked!"), "typed at the block's end: \(fieldValue())")
        XCTAssertEqual(canvasState()["writing"] as? String, writing, "still writing the same block")

    }

    func testOriginalRevertsAndCleanUpStillWorks() {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("we walked ")
        ask.tap()
        ask.typeText("make it warmer")
        go.tap()
        XCTAssertTrue(waitForField("BEGINSWITH", "(rewritten -- mock)"), "\(fieldValue())")

        app.buttons["style.ai.original"].tap()
        XCTAssertTrue(waitForField("==", "we walked "), "Original reverts: \(fieldValue())")
        XCTAssertTrue(app.buttons["style.ai.original"].isSelected)

        app.buttons["style.ai.clean"].tap()
        XCTAssertTrue(waitForField("==", "we walked"), "Clean up rewrites: \(fieldValue())")
        XCTAssertTrue(app.buttons["style.ai.clean"].isSelected)
    }

    /// The keyboard's Go key sends as the Go pill does, and the writing
    /// goes on with the caret back in the block.
    func testTheKeyboardsGoKeySendsAndKeepsTheWriting() {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("we walked")
        let writing = canvasState()["writing"] as? String ?? ""
        ask.tap()
        ask.typeText("make it warmer\n")
        XCTAssertTrue(waitForField("==", "(rewritten -- mock) we walked"), "\(fieldValue())")
        XCTAssertEqual(canvasState()["writing"] as? String, writing, "still writing the same block")
        app.typeText("!")
        XCTAssertTrue(waitForField("==", "(rewritten -- mock) we walked!"),
                      "the caret is in the block: \(fieldValue())")
    }

    /// The mic tapped while the caret is in the empty box: the waveform
    /// takes the box's place and the caret goes back to the block, which
    /// the words land in. The writing goes on.
    func testTheMicFromTheChatBoxKeepsTheWriting() {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("we walked")
        let writing = canvasState()["writing"] as? String ?? ""
        ask.tap()
        mic.tap()
        let live = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Listening..."), object: mic)
        XCTAssertEqual(XCTWaiter().wait(for: [live], timeout: 5), .completed, "the mic is live")
        XCTAssertEqual(canvasState()["writing"] as? String, writing, "still writing the same block")
        mic.tap()
        XCTAssertTrue(waitForField("BEGINSWITH", "we walked "), "the take landed in the block: \(fieldValue())")
        XCTAssertEqual(canvasState()["writing"] as? String, writing)
    }

    /// Go with no words in the block has nothing to rewrite.
    func testGoWaitsForWordsInTheBlock() {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        ask.tap()
        ask.typeText("make it warmer")
        XCTAssertTrue(go.waitForExistence(timeout: 3))
        XCTAssertFalse(go.isEnabled, "an empty block: Go is off")
    }

    /// "Edit text" on another block while writing opens it straight from
    /// this one. The chat box's words were this block's and stay behind,
    /// and Go then rewrites the new block (it used to do nothing once a Go
    /// had opened the Polish row on the first).
    func testGoRewritesABlockOpenedStraightFromAnother() {
        write("first block")
        write("second block")
        editText("first block")
        ask.tap()
        ask.typeText("make it warmer")
        go.tap()
        XCTAssertTrue(waitForField("==", "(rewritten -- mock) first block"), "\(fieldValue())")
        ask.tap()
        ask.typeText("and shorter")
        let first = canvasState()["writing"] as? String ?? ""

        editText("second block")
        XCTAssertNotEqual(canvasState()["writing"] as? String, first, "writing the second block")
        XCTAssertEqual(ask.value as? String ?? "", ask.placeholderValue ?? "",
                       "the first block's words stay with it")
        ask.tap()
        ask.typeText("make it warmer")
        go.tap()
        XCTAssertTrue(waitForField("==", "(rewritten -- mock) second block"), "Go rewrites it: \(fieldValue())")
    }

    /// `/rewrite` takes a block of at most 3000 code points. Exactly 3000
    /// goes. One more is not sent: the caption says why, and the words stay
    /// in the box with the block as it was.
    func testGoSendsABlockOf3000ButNotOneLonger() {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let block = String(repeating: "a", count: 3000)
        app.paste(block, into: field)
        XCTAssertTrue(waitForField("==", block), "pasted: \(fieldValue().count)")
        closeTheBlocksMenu()
        ask.tap()
        ask.typeText("make it shorter")
        go.tap()
        let rewritten = "(rewritten -- mock) " + block
        XCTAssertTrue(waitForField("==", rewritten), "3000 goes: \(fieldValue().prefix(40))")

        // The caret is back in the block: typing makes these words the
        // ones Go sends, 3021 code points.
        app.typeText("!")
        XCTAssertTrue(waitForField("==", rewritten + "!"))
        ask.tap()
        ask.typeText("make it shorter")
        go.tap()
        let tooLong = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "too long for Mira", "too long for Mira"
        )).firstMatch
        XCTAssertTrue(tooLong.waitForExistence(timeout: 3), "the caption says why")
        XCTAssertEqual(ask.value as? String, "make it shorter", "the words stay, to send again")
        XCTAssertEqual(fieldValue(), rewritten + "!", "the block is as it was")
    }

    /// The long press that pastes also opens the block's own menu (Edit
    /// text, Duplicate, ...), over the chat box. A tap closes the menu and
    /// does nothing else: the caret stays in the block.
    private func closeTheBlocksMenu() {
        let menu = app.buttons["Edit text"]
        guard menu.waitForExistence(timeout: 2) else { return }
        let writing = canvasState()["writing"] as? String
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 3), "the block's menu closed")
        XCTAssertEqual(canvasState()["writing"] as? String, writing, "still writing the block")
    }

    /// The block's menu, "Edit text", from wherever the page is.
    private func editText(_ words: String) {
        let block = app.staticTexts[words]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        block.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Edit text"].waitForExistence(timeout: 3))
        app.buttons["Edit text"].tap()
        XCTAssertTrue(waitForField("==", words), "writing '\(words)': \(fieldValue())")
    }

    /// A page tap with the caret in the chat box ends the writing, as it
    /// does with the caret in the block.
    func testAPageTapFromTheChatBoxEndsTheWriting() {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("we walked")
        ask.tap()
        ask.typeText("make")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 200, dy: 160)).tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5), "the writing ended")
        XCTAssertEqual(canvasState()["writing"] as? String, "")
    }
}
