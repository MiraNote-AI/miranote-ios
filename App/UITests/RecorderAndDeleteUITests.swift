import XCTest

/// Handoff screens 08 and 22: the live recording bar can throw the take
/// away, and an element dropped below the canvas is deleted (one tap from
/// undone).
final class RecorderAndDeleteUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        app.buttons["Start a memory"].tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testDiscardThrowsTheTakeAway() {
        XCTAssertTrue(app.buttons["mode.voice"].waitForExistence(timeout: 5))
        app.buttons["mode.voice"].tap()
        app.buttons["recorder.record"].tap()
        let discard = app.buttons["recorder.discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recorder.stop"].exists)

        discard.tap()
        let stop = app.buttons["recorder.stop"]
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: stop)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["recorder.record"].exists, "back to the dock, not re-armed")
        XCTAssertFalse(app.buttons["recorder.keep"].exists, "no result sheet: the take is gone")
        XCTAssertFalse(app.staticTexts["tap to play"].exists, "and no marker was placed")
        XCTAssertFalse(pendingMarker.exists, "nor is one still pulsing")
    }

    // Screen 08: while recording, a marker pulses where the take will
    // land; the live bar shows the clock.
    func testRecordingShowsWhereTheTakeWillLand() {
        startRecording()
        XCTAssertTrue(pendingMarker.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "voice recording"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // Screen 09: Stop attaches the take at once; Revert takes it off the
    // page again and Voice records a new one -- re-record is Revert + Voice.
    func testRevertTakesTheAttachedSoundOffAndVoiceRecordsAgain() {
        startRecording()
        let pendingFrame = pendingMarker.frame
        app.buttons["recorder.stop"].tap()

        let revert = app.buttons["recorder.revert"]
        XCTAssertTrue(revert.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sound is attached."].exists)
        XCTAssertLessThan(app.buttons["recorder.keep"].frame.maxY, app.buttons["mode.voice"].frame.minY,
                          "the sheet floats above the tool bar, which stays usable")
        let marker = app.staticTexts["tap to play"]
        XCTAssertTrue(marker.exists, "attached before any choice")
        XCTAssertEqual(app.buttons["sound.play"].frame.midX, pendingFrame.midX, accuracy: 2,
                       "the take lands where its marker pulsed")
        XCTAssertEqual(app.buttons["sound.play"].frame.midY, pendingFrame.midY, accuracy: 2)
        XCTAssertEqual(app.textFields["mira.input"].placeholderValue, "Ask Mira to adjust sound...",
                       "the composer speaks of sound")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "sound attached"
        shot.lifetime = .keepAlways
        add(shot)

        revert.tap()
        waitGone(marker)
        XCTAssertFalse(app.buttons["recorder.keep"].exists, "the sheet leaves with the take")
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled, "nothing left to undo on a fresh page")

        app.buttons["mode.voice"].tap()
        XCTAssertTrue(app.buttons["recorder.record"].waitForExistence(timeout: 5), "Voice records again")
    }

    // Any other change while the sheet shows makes Revert dishonest: the
    // sheet steps aside and the take stays.
    func testAnotherEditKeepsTheAttachedSound() {
        startRecording()
        app.buttons["recorder.stop"].tap()
        XCTAssertTrue(app.buttons["recorder.revert"].waitForExistence(timeout: 5))
        addTextBlock("after the take")
        XCTAssertFalse(app.buttons["recorder.revert"].exists)
        XCTAssertTrue(app.staticTexts["tap to play"].exists)
    }

    private var pendingMarker: XCUIElement {
        app.descendants(matching: .any)["recorder.pendingMarker"]
    }

    private func startRecording() {
        XCTAssertTrue(app.buttons["mode.voice"].waitForExistence(timeout: 5))
        app.buttons["mode.voice"].tap()
        app.buttons["recorder.record"].tap()
        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 5))
    }

    private func waitGone(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
    }

    func testDroppingBelowTheCanvasDeletesThenUndoRestores() {
        addTextBlock("drop me in the bin")
        let title = app.staticTexts["drop me in the bin"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        // The tool bar sits below the canvas: the delete zone.
        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let bin = app.buttons["mode.voice"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.08, thenDragTo: bin)

        let undo = app.buttons["toast.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(title.exists)
        XCTAssertFalse(app.descendants(matching: .any)["canvas.deleteZone"].exists, "the zone leaves with the drag")

        undo.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }

    private func addTextBlock(_ text: String) {
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text)
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }
}
