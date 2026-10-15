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

    private func waitGone(_ element: XCUIElement, _ message: String) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, message)
    }

    // MARK: 06

    // The composer opens the chat: the question field, Mira's four quick
    // actions, the dictation strip; Done closes it and the draft waits in
    // the composer, ready to send.
    func testComposerOpensTheChatAndADraftWaits() {
        app.openMiraChat()
        for action in ["Change background", "Re-layout photos", "Make text warmer", "Add soft title"] {
            XCTAssertTrue(app.buttons["mira.action.\(action)"].exists, "\(action) chip")
        }
        XCTAssertTrue(app.descendants(matching: .any)["mira.dictation"].exists, "the dictation strip")
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
        app.openMiraChat()
        app.buttons["mira.action.Make text warmer"].tap()
        waitGone(app.miraInput, "the chat steps aside for the turn")
        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 8), "warmer polished the text")
    }

    // Hold to talk: the words land in the question for editing -- nothing
    // is sent by itself.
    func testHoldToDictateFillsTheQuestion() {
        app.openMiraChat()
        let strip = app.descendants(matching: .any)["mira.dictation"]
        strip.press(forDuration: 1.2)
        let filled = NSPredicate(format: "value CONTAINS %@", "Transcribed voice note (mock)")
        expectation(for: filled, evaluatedWith: app.miraInput)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.miraInput.exists, "still in the chat, nothing sent")
        XCTAssertFalse(app.staticTexts["mira.receipt"].exists)
    }

    // A quick tap (how VoiceOver, Voice Control and Switch Control
    // activate it) leaves the mic listening; the next tap ends the take.
    func testATapTogglesTheDictationStrip() {
        app.openMiraChat()
        let strip = app.descendants(matching: .any)["mira.dictation"]
        strip.tap()
        expectation(for: NSPredicate(format: "value == %@", "Listening..."), evaluatedWith: strip)
        waitForExpectations(timeout: 5)
        XCTAssertFalse((app.miraInput.value as? String ?? "").contains("Transcribed"), "nothing taken yet")

        strip.tap()
        let filled = NSPredicate(format: "value CONTAINS %@", "Transcribed voice note (mock)")
        expectation(for: filled, evaluatedWith: app.miraInput)
        waitForExpectations(timeout: 5)
    }

    // MARK: 07

    // Opening Background moves on from a waiting result: the sheet would
    // cover the curated sets and One-tap layout.
    func testOpeningBackgroundClosesTheResultSheet() {
        addText("sunny afternoon by the bridge")
        app.askMira("polish the text")
        XCTAssertTrue(app.buttons["mira.keep"].waitForExistence(timeout: 8))

        app.buttons["mode.background"].tap()
        waitGone(app.buttons["mira.keep"], "the result sheet steps aside for the tool")
        app.buttons["Canvas"].tap()
        XCTAssertTrue(app.staticTexts["(polished -- mock) sunny afternoon by the bridge"].waitForExistence(timeout: 5),
                      "and the change is kept")
    }

    // The result sheet says what changed and what was kept, waits for the
    // choice (no auto-keep), turns Save forest meanwhile, and the composer
    // offers to refine. Keep keeps; Revert restores.
    func testResultSheetWaitsThenKeepsOrReverts() {
        addText("sunny afternoon by the bridge")
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
        // Done left the block selected (screen 21), which still offers to
        // refine; with nothing selected the composer is back to asking.
        XCTAssertEqual(app.miraComposer.label, "Ask Mira to refine...")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        XCTAssertEqual(app.miraComposer.label, "Ask Mira anything")

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
