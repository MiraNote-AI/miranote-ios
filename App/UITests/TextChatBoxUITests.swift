import XCTest

/// #205 PR 3, the chat box while writing: its trailing button is the mic
/// while it is empty and Go once there are words (F7A); the caret moves
/// there and back without ending the writing; Go has Mira rewrite the
/// block, previewed in place on the Polish row with no chip selected (F6B,
/// H3A). Under -UITEST the rewrite is the mock's ("make it warmer" asks a
/// polish).
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

        XCTAssertTrue(waitForField("==", "(polished -- mock) we walked"),
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
        XCTAssertTrue(waitForField("==", "(polished -- mock) we walked!"), "typed at the block's end: \(fieldValue())")
        XCTAssertEqual(canvasState()["writing"] as? String, writing, "still writing the same block")

    }

    func testOriginalRevertsAndCleanUpStillWorks() {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("we walked ")
        ask.tap()
        ask.typeText("make it warmer")
        go.tap()
        XCTAssertTrue(waitForField("BEGINSWITH", "(polished -- mock)"), "\(fieldValue())")

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
        XCTAssertTrue(waitForField("==", "(polished -- mock) we walked"), "\(fieldValue())")
        XCTAssertEqual(canvasState()["writing"] as? String, writing, "still writing the same block")
        app.typeText("!")
        XCTAssertTrue(waitForField("==", "(polished -- mock) we walked!"), "the caret is in the block: \(fieldValue())")
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
