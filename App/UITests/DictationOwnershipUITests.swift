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

    /// Monkey seed 1001: Voice's Record, then the Sticker tool while the
    /// mic is still coming up. The canvas let go of the recorder, but the
    /// mic came up anyway and stayed on with nothing showing it.
    func testLeavingWhileTheVoiceMicComesUpLeavesNoMicOn() {
        startAMemory(["-MIC_START_DELAY", "1500"])
        app.buttons["mode.voice"].tap()
        let record = app.buttons["recorder.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        app.buttons["mode.sticker"].tap()
        sleep(3)
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state").firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        XCTAssertTrue(probe.label.contains("\"micLive\":0"), "a mic is on behind the Sticker scene: \(probe.label)")
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

    /// A new, empty block: dictate, then Done while "Writing it down...".
    /// Done waits inside the session, completes when the words arrive, the
    /// words are in the block, and one undo takes the block back.
    func testDoneRightAfterDictatingIntoANewBlockWaitsForTheWords() {
        startAMemory(["-TRANSCRIBE_DELAY", "3000"])
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        strip.press(forDuration: 0.8)
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["keyboard.done"].exists, "Done waits while the words are on their way")
        XCTAssertEqual(strip.value as? String, "Writing it down...")
        waitGone(app.buttons["keyboard.done"], "Done completes once the words arrive")
        XCTAssertTrue(dictatedWords.waitForExistence(timeout: 3), "words dictated into the new block are kept")

        app.buttons["editor.undo"].tap()
        waitGone(dictatedWords, "one undo takes the dictated block back")
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled, "no step left showing an empty block")
    }

    /// A new block: dictate, then tap empty paper while "Writing it
    /// down...". The tap waits like Done, the words land in the block, and
    /// then the tap's deselect follows.
    func testATapOnThePaperWhileTranscribingWaitsForTheWords() {
        startAMemory(["-TRANSCRIBE_DELAY", "3000"])
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        strip.press(forDuration: 0.8)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.5)).tap()
        XCTAssertTrue(app.buttons["keyboard.done"].exists, "the tap waits while the words are on their way")
        XCTAssertEqual(strip.value as? String, "Writing it down...")
        waitGone(app.buttons["keyboard.done"], "the session ends once the words arrive")
        XCTAssertTrue(dictatedWords.waitForExistence(timeout: 3), "the words land in the new block")
        XCTAssertEqual(app.miraComposer.label, "Ask Mira anything", "and nothing is selected")
    }

    /// A hold started while that tap waits is a take of the same session:
    /// when the first words land it is still listening, and its words land
    /// too before the tap ends the writing.
    func testAHoldWhileATapWaitsLandsItsWordsToo() {
        startAMemory(["-TRANSCRIBE_DELAY", "3000"])
        write("Lunch")
        strip.press(forDuration: 0.8)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.5)).tap()
        XCTAssertTrue(app.buttons["keyboard.done"].exists, "the tap waits while the words are on their way")
        strip.press(forDuration: 4)
        let both = app.staticTexts["Lunch Transcribed voice note (mock) Transcribed voice note (mock)"]
        XCTAssertTrue(both.waitForExistence(timeout: 10), "the second take's words never landed")
        XCTAssertFalse(app.buttons["keyboard.done"].exists, "the tap ended the writing after both")
    }

    /// Same with a tap on another element: the words land, then that
    /// element is the one selected (a second tap writes in it).
    func testATapOnAnotherElementWhileTranscribingWaitsThenSelectsIt() {
        startAMemory(["-TRANSCRIBE_DELAY", "3000"])
        write("Lunch")
        app.buttons["keyboard.done"].tap()
        waitGone(app.buttons["keyboard.done"], "writing ended")
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        strip.press(forDuration: 0.8)
        app.staticTexts["Lunch"].tap()
        XCTAssertTrue(app.buttons["keyboard.done"].exists, "the tap waits while the words are on their way")
        waitGone(app.buttons["keyboard.done"], "the session ends once the words arrive")
        XCTAssertTrue(dictatedWords.waitForExistence(timeout: 3), "the words land in the new block")
        XCTAssertEqual(app.miraComposer.label, "Ask Mira to refine...", "an element is selected")
        app.staticTexts["Lunch"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5), "a second tap writes in the tapped element")
        XCTAssertEqual(field.value as? String, "Lunch")
    }

    /// Two quick holds, the second while the first is still being written
    /// down (the natural way to dictate two phrases): both land, no extra
    /// tap in between.
    func testTwoQuickHoldsLandTwoPhrases() {
        startAMemory(["-TRANSCRIBE_DELAY", "4000"])
        write("Lunch")
        strip.press(forDuration: 0.8)
        strip.press(forDuration: 0.8)
        let both = "Lunch Transcribed voice note (mock) Transcribed voice note (mock)"
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", both), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 12), .completed, "the second hold's words land too")
    }

    /// A take of a cancelled session still being written down (held 20 s)
    /// never holds back the next session's take.
    func testACancelledSessionsSlowTakeNeverDelaysTheNext() {
        startAMemory(["-TRANSCRIBE_FIRST_DELAY", "20000"])
        write("Lunch")
        strip.press(forDuration: 0.8)
        app.buttons["text.cancel"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        write("Dinner")
        strip.press(forDuration: 0.8)
        let landed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Dinner Transcribed voice note (mock)"), object: field
        )
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 6), .completed, "the new take waited for the old one")
    }

    /// The same block reopened while a cancelled session's take is still
    /// on its way: only the new session's take lands in it.
    func testACancelledTakeNeverLandsInTheSameBlockReopened() {
        startAMemory(["-TRANSCRIBE_DELAY", "3000"])
        write("Lunch")
        app.buttons["keyboard.done"].tap()
        waitGone(app.buttons["keyboard.done"], "writing ended")
        let lunch = app.staticTexts["Lunch"]
        for take in 0..<2 {
            lunch.tap()
            if !field.waitForExistence(timeout: 2) { lunch.tap() }
            XCTAssertTrue(field.waitForExistence(timeout: 5), "the block reopens (\(take))")
            strip.press(forDuration: 0.8)
            if take == 0 {
                app.buttons["text.cancel"].tap()
                XCTAssertTrue(field.waitForNonExistence(timeout: 5))
            }
        }
        app.buttons["keyboard.done"].tap()
        let once = app.staticTexts["Lunch Transcribed voice note (mock)"]
        XCTAssertTrue(once.waitForExistence(timeout: 8), "the new take lands, once")
        sleep(2)
        XCTAssertTrue(once.exists, "the cancelled take landed too")
    }

    /// Meng's probe: a hold across a cancelled take's return, then Done --
    /// the new words land and no mic is left on.
    func testAHoldAcrossAnOldTakesReturnThenDoneLeavesNoMicOn() {
        startAMemory(["-TRANSCRIBE_DELAY", "6000"])
        write("Lunch")
        strip.press(forDuration: 0.8)
        app.buttons["text.cancel"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        write("Dinner")
        // Typing took a few seconds: the old take returns during the hold.
        strip.press(forDuration: 6)
        app.buttons["keyboard.done"].tap()
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.buttons["keyboard.done"])
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 9), .completed, "Done completes once the words land")
        XCTAssertTrue(dictatedWords.waitForExistence(timeout: 3), "the new take's words land")
        assertVoiceRecords("the strip's mic did not stay on")
    }

    /// Done while the strip still listens (the tap toggle): the take stops
    /// and Done waits for its words, like a take already stopped.
    func testDoneWhileListeningStopsTheTakeAndKeepsItsWords() {
        startAMemory(["-TRANSCRIBE_DELAY", "1500"])
        write("Lunch")
        strip.tap()
        let listening = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Listening...'"),
                                                  object: strip)
        XCTAssertEqual(XCTWaiter().wait(for: [listening], timeout: 5), .completed)
        app.buttons["keyboard.done"].tap()
        waitGone(app.buttons["keyboard.done"], "Done completes once the words land")
        XCTAssertTrue(dictatedWords.waitForExistence(timeout: 3), "the listening take's words are kept")
        assertVoiceRecords("the strip's mic did not stay on")
    }

    /// The Mira strip: a hold across the first take's return, then Done --
    /// no mic is left on, and both phrases are in the question.
    func testMiraStripHoldAcrossTheFirstTakesReturnLeavesNoMicOn() {
        startAMemory(["-TRANSCRIBE_DELAY", "1500"])
        app.openMiraChat()
        let miraStrip = app.descendants(matching: .any)["mira.dictation"]
        miraStrip.press(forDuration: 0.8)
        miraStrip.press(forDuration: 3)
        let both = NSPredicate(format: "value CONTAINS %@",
                               "Transcribed voice note (mock) Transcribed voice note (mock)")
        let landed = XCTNSPredicateExpectation(predicate: both, object: app.miraInput)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 8), .completed, "both phrases land")
        app.buttons["Done"].tap()
        waitGone(app.miraInput, "Done closes the chat")
        assertVoiceRecords("the Mira strip's mic did not stay on")
    }

    /// Two holds on the Mira strip, the first written down slowly: the
    /// question reads them in the order spoken.
    func testMiraStripTakesLandInTheOrderSpoken() {
        startAMemory(["-TRANSCRIBE_FIRST_DELAY", "4000", "-NUMBER_TAKES"])
        app.openMiraChat()
        let miraStrip = app.descendants(matching: .any)["mira.dictation"]
        miraStrip.press(forDuration: 0.8)
        miraStrip.press(forDuration: 0.8)
        let both = NSPredicate(format: "value CONTAINS %@ AND value CONTAINS %@", "#1", "#2")
        let landed = XCTNSPredicateExpectation(predicate: both, object: app.miraInput)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 12), .completed, "both phrases land")
        XCTAssertEqual(app.miraInput.value as? String,
                       "Transcribed voice note (mock) #1 Transcribed voice note (mock) #2")
    }

    /// A take that fails keeps its notice on the strip when a later take
    /// lands, so the lost phrase is explained.
    func testAFailedMiraTakeKeepsItsNoticeWhenTheNextLands() {
        startAMemory(["-TRANSCRIBE_DELAY", "1500", "-FAIL_FIRST_TAKE"])
        app.openMiraChat()
        let miraStrip = app.descendants(matching: .any)["mira.dictation"]
        miraStrip.press(forDuration: 0.8)
        miraStrip.press(forDuration: 0.8)
        let filled = NSPredicate(format: "value CONTAINS %@", "Transcribed voice note (mock)")
        let landed = XCTNSPredicateExpectation(predicate: filled, object: app.miraInput)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 8), .completed, "the second phrase lands")
        XCTAssertEqual(miraStrip.value as? String, "Couldn't reach the transcriber -- try again?")
    }

    /// Same, but the words do not come within the wait's cap: the session
    /// ends without them, the empty block goes, and Home at once files no
    /// "New memory" page.
    func testHomeAfterTheWaitRanOutFilesNoPage() {
        startAMemory(["-TRANSCRIBE_DELAY", "14000"])
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        strip.press(forDuration: 0.8)
        app.buttons["keyboard.done"].tap()
        let home = app.buttons["nav.leading"]
        let homeShows = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Home'"), object: home)
        XCTAssertEqual(XCTWaiter().wait(for: [homeShows], timeout: 13), .completed, "the wait ends at its cap")
        XCTAssertTrue(app.staticTexts["Couldn't catch those words."].exists, "the page says why")
        XCTAssertFalse(field.exists, "the empty block went")
        home.tap()

        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5))
        app.buttons["collection.Daily Log"].tap()
        let filed = NSPredicate(format: "identifier BEGINSWITH 'note.' AND identifier != 'note.add'")
        let covers = app.buttons.matching(filed)
        XCTAssertTrue(covers.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(covers.count, 2, "Daily Log stays at its seeded 2 notes")
    }

    /// Meng's probe: while the words are on their way the keyboard stays
    /// up, so a drag of another element toward the bottom of the screen
    /// runs behind it -- it must not delete there, unseen.
    func testADragWhileTheKeyboardIsUpNeverDeletes() {
        startAMemory(["-TRANSCRIBE_DELAY", "3000"])
        write("Lunch")
        app.buttons["keyboard.done"].tap()
        waitGone(app.buttons["keyboard.done"], "writing ended")
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        strip.press(forDuration: 0.8)
        let lunch = app.staticTexts["Lunch"]
        lunch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)))
        waitGone(app.buttons["keyboard.done"], "the session ends once the words land")
        sleep(1)
        XCTAssertTrue(lunch.exists, "the drag behind the keyboard deleted the block")
        XCTAssertFalse(app.buttons["toast.undo"].exists)
    }

    /// Cancel while "Writing it down...": the words are dropped with the
    /// session. An existing block, reopened: it stays on the page, so only
    /// the session's guard keeps the late words out of it.
    func testCancelWhileTranscribingDropsTheWords() {
        startAMemory(["-TRANSCRIBE_DELAY", "1500"])
        write("Lunch")
        app.buttons["keyboard.done"].tap()
        waitGone(app.buttons["keyboard.done"], "writing ended")
        let lunch = app.staticTexts["Lunch"]
        lunch.tap()
        if !field.waitForExistence(timeout: 2) { lunch.tap() }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the block reopens")
        strip.press(forDuration: 0.8)
        app.buttons["text.cancel"].tap()
        sleep(3)
        XCTAssertFalse(dictatedWords.exists, "Cancel keeps nothing of the session")
        XCTAssertTrue(lunch.exists, "the block keeps its words")
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
