import XCTest

/// One audio owner at a time on the canvas, and no mic left on that nobody
/// sees: the dictation strips, the Voice tool and the Text beat hand over
/// cleanly. A slow mic (`-MIC_START_DELAY`) and a slow transcriber
/// (`-TRANSCRIBE_DELAY`) open the windows a real device has.
final class DictationOwnershipUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func startAMemory(_ arguments: [String] = []) {
        app.launchArguments = ["-UITEST"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    private var field: XCUIElement { app.descendants(matching: .any)["canvas.textEditor"] }
    private var strip: XCUIElement { app.descendants(matching: .any)["style.mic"] }

    private func write(_ words: String) {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
    }

    private func waitGone(_ element: XCUIElement, _ message: String) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, message)
    }

    /// Voice records: the Voice tool's Record goes live (nobody else holds the mic).
    private func assertVoiceRecords(_ message: String) {
        app.buttons["mode.voice"].tap()
        let record = app.buttons["recorder.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5), "Voice arms: \(message)")
        record.tap()
        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 5), "Voice records: \(message)")
    }

    private var dictatedWords: XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Transcribed")).firstMatch
    }

    // MARK: Who holds the mic

    /// An armed Voice tool holds no audio: text dictation still works.
    func testArmedVoiceDoesNotBlockDictation() {
        startAMemory()
        app.buttons["mode.voice"].tap()
        XCTAssertTrue(app.buttons["recorder.record"].waitForExistence(timeout: 5))
        write("caption")
        strip.press(forDuration: 0.8)
        let landed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "Transcribed"), object: field
        )
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 4), .completed,
                       "an armed (not recording) Voice tool must not block dictation")
    }

    /// The Mira chat closes while its mic is still coming up: the mic
    /// stops once it is up, and Voice records afterwards.
    func testClosingTheChatWhileItsMicComesUpLeavesNoMicOn() {
        startAMemory(["-MIC_START_DELAY", "1500"])
        app.openMiraChat()
        app.descendants(matching: .any)["mira.dictation"].tap()
        app.buttons["Done"].tap()
        waitGone(app.miraInput, "Done closes the chat")
        sleep(2)
        assertVoiceRecords("the chat's mic did not stay on")
    }

    /// Writing ends while the strip's mic is still coming up: same.
    func testEndingTheWritingWhileItsMicComesUpLeavesNoMicOn() {
        startAMemory(["-MIC_START_DELAY", "1500"])
        write("caption")
        strip.tap()
        app.buttons["keyboard.done"].tap()
        waitGone(app.buttons["keyboard.done"], "writing ended")
        sleep(2)
        assertVoiceRecords("the strip's mic did not stay on")
    }

    // MARK: Words on their way

    /// Done while "Writing it down...": the words still land in the block.
    func testDoneWhileTranscribingKeepsTheWords() {
        startAMemory(["-TRANSCRIBE_DELAY", "1500"])
        write("Lunch")
        strip.press(forDuration: 0.8)
        app.buttons["keyboard.done"].tap()
        waitGone(app.buttons["keyboard.done"], "writing ended")
        XCTAssertTrue(dictatedWords.waitForExistence(timeout: 6), "words dictated just before Done are kept")
    }

    /// Cancel while "Writing it down...": the words are dropped with the session.
    func testCancelWhileTranscribingDropsTheWords() {
        startAMemory(["-TRANSCRIBE_DELAY", "1500"])
        write("Lunch")
        strip.press(forDuration: 0.8)
        app.buttons["text.cancel"].tap()
        sleep(3)
        XCTAssertFalse(dictatedWords.exists, "Cancel keeps nothing of the session")
        XCTAssertFalse(field.exists, "and no writing session opens for them")
    }

    // MARK: The Text beat

    /// Text, then Sticker within the beat (stretched to 3 s): coming back
    /// lands on the canvas, not in a writing session nobody asked for.
    func testLeavingDuringTheTextBeatStartsNoSession() {
        startAMemory(["-TEXT_MODE_BEAT", "3000"])
        app.buttons["mode.text"].tap()
        app.buttons["mode.sticker"].tap()
        XCTAssertTrue(app.buttons["sticker.tab.make"].waitForExistence(timeout: 5))
        sleep(4)
        app.buttons["nav.leading"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertFalse(field.exists, "no writing session on return")
        XCTAssertFalse(app.buttons["text.cancel"].exists, "the header is not in writing mode")
    }
}
