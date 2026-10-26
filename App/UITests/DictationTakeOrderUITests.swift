import XCTest

/// A take spoken while earlier words are still on their way: it lands, in
/// the order spoken, and an earlier take's failure stays explained. The
/// delay and transcript hooks are in docs/testing/adversarial-harness.md.
final class DictationTakeOrderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func startAMemory(_ arguments: [String]) {
        app.launchArguments = ["-UITEST"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    private var field: XCUIElement { app.descendants(matching: .any)["canvas.textEditor"] }
    private var strip: XCUIElement { app.descendants(matching: .any)["style.mic"] }
    private var miraStrip: XCUIElement { app.descendants(matching: .any)["mira.dictation"] }

    /// A tap on the paper waits for the words; a hold started while it waits
    /// is a take of the same session: when the first words land it is still
    /// listening, and its words land too before the tap ends the writing.
    func testAHoldWhileATapWaitsLandsItsWordsToo() {
        startAMemory(["-TRANSCRIBE_DELAY", "3000"])
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Lunch")
        strip.press(forDuration: 0.8)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.5)).tap()
        XCTAssertTrue(app.buttons["keyboard.done"].exists, "the tap waits while the words are on their way")
        strip.press(forDuration: 4)
        let both = app.staticTexts["Lunch Transcribed voice note (mock) Transcribed voice note (mock)"]
        XCTAssertTrue(both.waitForExistence(timeout: 10), "the second take's words never landed")
        XCTAssertFalse(app.buttons["keyboard.done"].exists, "the tap ended the writing after both")
    }

    /// A hold still down when the earlier take's words land keeps recording
    /// until the finger lifts: its words are the whole hold, in the same
    /// block, and the tap ends the writing after them.
    func testAHoldStillDownWhenTheWordsLandIsKeptWhole() {
        startAMemory(["-TRANSCRIBE_FIRST_DELAY", "3000", "-TIME_TAKES"])
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Lunch")
        strip.press(forDuration: 0.8)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.5)).tap()
        XCTAssertTrue(app.buttons["keyboard.done"].exists, "the tap waits while the words are on their way")
        strip.press(forDuration: 5)
        let whole = app.staticTexts["Lunch Transcribed voice note (mock) (1 s) Transcribed voice note (mock) (5 s)"]
        let block = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Lunch'")).firstMatch
        XCTAssertTrue(whole.waitForExistence(timeout: 10), "the held take was cut short: \(block.label)")
        XCTAssertFalse(app.buttons["keyboard.done"].exists, "the tap ended the writing after both")
    }

    /// Two holds on the Mira strip, the first written down slowly: the
    /// question reads them in the order spoken.
    func testMiraStripTakesLandInTheOrderSpoken() {
        startAMemory(["-TRANSCRIBE_FIRST_DELAY", "4000", "-NUMBER_TAKES"])
        app.openMiraChat()
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
        miraStrip.press(forDuration: 0.8)
        miraStrip.press(forDuration: 0.8)
        let filled = NSPredicate(format: "value CONTAINS %@", "Transcribed voice note (mock)")
        let landed = XCTNSPredicateExpectation(predicate: filled, object: app.miraInput)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 8), .completed, "the second phrase lands")
        XCTAssertEqual(miraStrip.value as? String, "Couldn't reach the transcriber -- try again?")
    }
}
