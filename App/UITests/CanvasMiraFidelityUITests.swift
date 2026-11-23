import XCTest

/// Handoff screens 06 (Mira canvas chat), 07 (Mira result) and 22 (drag to
/// delete), deterministic under -UITEST.
final class CanvasMiraFidelityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func addText(_ words: String) {
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
        app.buttons["keyboard.done"].tap()
    }

    /// The Mira chat's mic, on the question box's right.
    private var miraMic: XCUIElement { app.descendants(matching: .any)["mira.dictation"] }

    private func waitGone(_ element: XCUIElement, _ message: String) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, message)
    }

    // MARK: 06

    // A typed turn shows exactly as typed: no Markdown, and words that are
    // also app copy ("Done") are not looked up in the string catalog.
    func testATypedTurnShowsAsTyped() {
        app.askMira("Done *x*")
        XCTAssertTrue(app.staticTexts["Done *x*"].waitForExistence(timeout: 8), "the turn reads as typed")
    }

    // The composer opens the chat: the question field, Mira's four quick
    // actions, the mic; Done closes it and the draft waits in the composer,
    // ready to send.
    func testComposerOpensTheChatAndADraftWaits() {
        app.openMiraChat()
        for action in ["Change background", "Re-layout photos", "Make text warmer", "Add soft title"] {
            XCTAssertTrue(app.buttons["mira.action.\(action)"].exists, "\(action) chip")
        }
        XCTAssertTrue(miraMic.exists, "the mic")
        XCTAssertTrue(app.buttons["Canvas"].exists, "the way back reads Canvas")

        app.miraInput.typeText("a draft for later")
        app.buttons["Done"].tap()
        waitGone(app.miraInput, "Done closes the chat")
        XCTAssertEqual(app.miraComposer.label, "a draft for later", "the draft waits in the composer")
        XCTAssertTrue(app.buttons["mira.go"].isEnabled)
    }

    // A quick action closes the chat and runs its turn.
    func testAQuickActionRunsItsTurn() {
        addText("sunny afternoon by the bridge")
        app.letGoOfTheSelection()
        app.openMiraChat()
        app.buttons["mira.action.Make text warmer"].tap()
        waitGone(app.miraInput, "the chat steps aside for the turn")
        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 8), "warmer polished the text")
    }

    // Return as its own key press after a several-word ask sends it (the
    // one-call typing is askMira's, above).
    func testReturnAsItsOwnKeyPressSendsTheAsk() {
        addText("sunny afternoon by the bridge")
        app.letGoOfTheSelection()
        app.openMiraChat()
        app.miraInput.tap()
        app.miraInput.typeText("polish the text")
        app.miraInput.typeText("\n")
        waitGone(app.miraInput, "the chat steps aside for the turn")
        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 8), "the ask ran")
    }

    // A paste never sends, even lines that end in a new line.
    func testAPastedMultiLineAskIsNotSent() {
        app.openMiraChat()
        app.miraInput.tap()
        app.paste("polish the text\nand make it warmer\n", into: app.miraInput)
        sleep(2)
        XCTAssertTrue(app.miraInput.exists, "still in the chat: nothing was sent")
        XCTAssertTrue((app.miraInput.value as? String ?? "").contains("polish the text"), "the words wait")
        XCTAssertFalse(app.staticTexts["mira.receipt"].exists)
    }

    // Option B (team lead, 2026-11-22): the question is asked from the
    // writing chat box at the bottom -- just above the keyboard, above the
    // home indicator with it down -- with the mic on its right. No
    // dictation strip, no dark capsule under the header.
    func testTheQuestionBoxSitsAtTheBottomWithItsMic() {
        app.openMiraChat()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        // The keyboard is in the tree before it has slid in.
        for _ in 0..<30 where keyboard.frame.minY >= app.frame.maxY { usleep(100_000) }
        XCTAssertLessThan(keyboard.frame.minY, app.frame.maxY, "the keyboard is up")
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertLessThan(miraMic.frame.width, 60, "the mic is a button in the box, not the full-width strip")
        let panel = app.staticTexts["Mira can edit this canvas directly."]
        let field = app.miraInput.frame, mic = miraMic.frame
        XCTAssertGreaterThan(field.minY, panel.frame.maxY + 40, "the box is under Mira's panel, not over it")
        XCTAssertEqual(mic.midY, field.midY, accuracy: 4, "the mic is in the box's row")
        XCTAssertGreaterThanOrEqual(mic.minX, field.maxX - 2, "the mic is on the box's right")
        // iOS 26 reports the keyboard's frame lower than it draws (the
        // suggestions row): the box is over that, and goes down with it.
        XCTAssertLessThan(mic.maxY, keyboard.frame.minY, "the box is over the keyboard")

        panel.tap()
        waitGone(keyboard, "a tap on the panel lowers the keyboard")
        for _ in 0..<30 where miraMic.frame.minY < mic.minY + 200 { usleep(100_000) }
        XCTAssertGreaterThan(miraMic.frame.minY - mic.minY, 200, "the box rode down with the keyboard")
        let aboveBottom = app.frame.maxY - miraMic.frame.maxY
        XCTAssertTrue((34...80).contains(aboveBottom), "the box sits over the home indicator: \(aboveBottom) pt")
    }

    // As the writing chat box: the mic while the box is empty, Go once
    // there are words, the mic again once they are cleared; Go sends.
    func testTheMicBecomesGoWithWordsAndGoSends() {
        addText("sunny afternoon by the bridge")
        app.letGoOfTheSelection()
        app.openMiraChat()
        let go = app.buttons["mira.ask"]
        XCTAssertTrue(miraMic.exists)
        XCTAssertFalse(go.exists, "no Go without words")
        app.miraInput.typeText("polish")
        XCTAssertTrue(go.waitForExistence(timeout: 3), "words bring Go")
        XCTAssertFalse(miraMic.exists, "Go takes the mic's place")
        app.miraInput.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
        XCTAssertTrue(miraMic.waitForExistence(timeout: 3), "cleared: the mic is back")
        app.miraInput.typeText("polish the text")
        go.tap()
        waitGone(app.miraInput, "Go sends: the chat steps aside for the turn")
        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 8), "the ask ran")
    }

    // The transcriber unreachable (a 503): the hint that lived in the strip
    // shows over the box, by the mic, as the writing chat box shows it; the
    // mic says it too.
    func testAnUnreachableTranscriberSaysSoByTheMic() {
        app.terminate()
        app.launchArguments += ["-FAIL_FIRST_TAKE"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        app.openMiraChat()
        miraMic.press(forDuration: 1.2)
        let hint = "Couldn't reach the transcriber -- try again?"
        let caption = app.staticTexts["mira.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 8), "the hint shows")
        XCTAssertEqual(caption.label, hint)
        XCTAssertEqual(miraMic.value as? String, hint)
        XCTAssertLessThan(caption.frame.maxY, miraMic.frame.minY + 6, "over the box, by the mic")
        XCTAssertEqual(app.miraInput.value as? String ?? "", "", "nothing landed")
    }

    // Hold to talk: the words land in the question for editing -- nothing
    // is sent by itself.
    func testHoldToDictateFillsTheQuestion() {
        app.openMiraChat()
        miraMic.press(forDuration: 1.2)
        let filled = NSPredicate(format: "value CONTAINS %@", "Transcribed voice note (mock)")
        expectation(for: filled, evaluatedWith: app.miraInput)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.miraInput.exists, "still in the chat, nothing sent")
        XCTAssertFalse(app.staticTexts["mira.receipt"].exists)
    }

    // A quick tap (how VoiceOver, Voice Control and Switch Control
    // activate it) leaves the mic listening; the next tap ends the take.
    func testATapTogglesTheMic() {
        app.openMiraChat()
        miraMic.tap()
        expectation(for: NSPredicate(format: "value == %@", "Listening..."), evaluatedWith: miraMic)
        waitForExpectations(timeout: 5)
        XCTAssertFalse((app.miraInput.value as? String ?? "").contains("Transcribed"), "nothing taken yet")

        miraMic.tap()
        let filled = NSPredicate(format: "value CONTAINS %@", "Transcribed voice note (mock)")
        expectation(for: filled, evaluatedWith: app.miraInput)
        waitForExpectations(timeout: 5)
    }

    // MARK: 07

    // Opening Background moves on from a waiting result: the sheet would
    // cover the tool's rows.
    func testOpeningBackgroundClosesTheResultSheet() {
        addText("sunny afternoon by the bridge")
        app.letGoOfTheSelection()
        app.askMira("polish the text")
        XCTAssertTrue(app.buttons["mira.keep"].waitForExistence(timeout: 8))

        app.buttons["mode.background"].tap()
        waitGone(app.buttons["mira.keep"], "the result sheet steps aside for the tool")
        app.closeBackground()
        XCTAssertTrue(app.staticTexts["(polished -- mock) sunny afternoon by the bridge"].waitForExistence(timeout: 5),
                      "and the change is kept")
    }

    // The result sheet says what changed and what was kept, waits for the
    // choice (no auto-keep), turns Save forest meanwhile, and the composer
    // offers to refine. Keep keeps; Revert restores.
    func testResultSheetWaitsThenKeepsOrReverts() {
        addText("sunny afternoon by the bridge")
        // Done left the block selected (screen 21), which offers to refine
        // it in place; with nothing selected the composer asks the chat.
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5))
        XCTAssertEqual(app.miraComposer.label, "Ask Mira to refine...")
        app.letGoOfTheSelection()
        XCTAssertEqual(app.miraComposer.label, "Ask Mira anything")
        app.askMira("polish the text")

        let receipt = app.staticTexts["mira.receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["mira.kept"].exists, "the kept line is back")
        XCTAssertTrue(app.buttons["mira.revert"].exists)
        XCTAssertTrue(app.buttons["mira.keep"].exists)
        XCTAssertEqual(app.miraComposer.label, "Ask Mira to refine...")

        sleep(3)
        XCTAssertTrue(receipt.exists, "the sheet waits for a choice")

        app.buttons["mira.keep"].tap()
        waitGone(receipt, "Keep closes the sheet")
        let polished = "(polished -- mock) sunny afternoon by the bridge"
        XCTAssertTrue(app.staticTexts[polished].exists, "and keeps the change")
        XCTAssertEqual(app.miraComposer.label, "Ask Mira anything", "nothing waits, nothing is selected")

        app.askMira("polish the text")
        XCTAssertTrue(receipt.waitForExistence(timeout: 8))
        app.buttons["mira.revert"].tap()
        waitGone(receipt, "Revert closes the sheet")
        XCTAssertTrue(app.staticTexts[polished].waitForExistence(timeout: 5), "Revert takes back only the last turn")
    }

    // MARK: 22

    // A drag shows the zone; over the composer it arms; the drop deletes.
    // XCUITest cannot look mid-drag, so the app leaves the phases it went
    // through on a -UITEST probe.
    func testDraggingShowsTheZoneAndArmsItOverTheComposer() {
        addText("drag me down")
        let words = app.staticTexts["drag me down"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))

        let start = words.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let composer = app.buttons["mira.go"].coordinate(withNormalizedOffset: CGVector(dx: -2, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: composer, withVelocity: .slow, thenHoldForDuration: 0.6)

        XCTAssertTrue(app.buttons["toast.undo"].waitForExistence(timeout: 5), "the drop deleted it")
        let trail = app.descendants(matching: .any)["canvas.deleteZone.trail"].label
        XCTAssertTrue(trail.contains("dragging"), "the zone came up with the drag: \(trail)")
        XCTAssertTrue(trail.contains("armed"), "and armed over the composer: \(trail)")
        XCTAssertTrue(trail.hasSuffix("none"), "and left with the drop: \(trail)")
        XCTAssertFalse(app.descendants(matching: .any)["canvas.deleteZone"].exists)
    }
}
