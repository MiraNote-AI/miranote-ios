import XCTest

/// #151: "How Mira uses AI" shows right before the first action that would
/// send page content, Not now sends nothing, Continue is kept, the mood
/// switch stops mood requests and withdrawing asks again. Other suites
/// launch consented; these launch with `-AI-CONSENT-ASK`. `aiSent` in the
/// debug probe counts the requests let past consent.
final class AIConsentUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: Helpers

    private func launch(asking: Bool, keep: Bool = false) {
        app.launchArguments = ["-UITEST"] + (asking ? ["-AI-CONSENT-ASK"] : []) + (keep ? ["-KEEP_SETTINGS"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
    }

    private var sheet: XCUIElement { app.staticTexts["aiConsent.title"] }
    private var field: XCUIElement { app.descendants(matching: .any)["canvas.textEditor"] }

    private func startWriting(_ words: String) {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
    }

    private func savePage(_ words: String) {
        startWriting(words)
        app.buttons["keyboard.done"].tap()
        app.buttons["Save"].tap()
    }

    private func openSettings() {
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.buttons["settings.appearance"].waitForExistence(timeout: 5))
    }

    private func backHome() {
        app.buttons["settings.back"].tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5))
    }

    private func openJar() {
        app.buttons["home.starJar"].tap()
        XCTAssertTrue(app.staticTexts["Star jar"].waitForExistence(timeout: 5))
    }

    /// The most requests any probe on screen counts (each scene has one).
    private var aiSent: Int { probeMax("aiSent") }

    /// The highest `key` any debug probe on screen reports.
    private func probeMax(_ key: String) -> Int {
        let probes = app.descendants(matching: .any).matching(identifier: "debug.state").allElementsBoundByIndex
        return probes.compactMap { probe -> Int? in
            guard let data = probe.label.data(using: .utf8),
                  let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return state[key] as? Int
        }.max() ?? -1
    }

    /// The line a cancelled action shows: why nothing happened.
    private var consentLine: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "needs your OK", "needs your OK"
        )).firstMatch
    }

    private func waitForLabel(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 8) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [match], timeout: timeout), .completed,
                       "label is \(element.label), expected \(expected)")
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 5) -> Bool {
        let reads = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [reads], timeout: timeout) == .completed
    }

    private func fieldValueContains(_ words: String, timeout: TimeInterval = 5) -> Bool {
        let reads = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", words), object: field)
        return XCTWaiter().wait(for: [reads], timeout: timeout) == .completed
    }

    // MARK: Tests

    func testNotNowSendsNothingAndContinueIsNeverAskedAgain() {
        launch(asking: true)
        XCTAssertFalse(sheet.exists, "nothing at launch")
        startWriting("noodle shop")
        app.buttons["style.ai"].tap()
        app.buttons["style.ai.expand"].tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "the first AI action asks")

        app.buttons["aiConsent.details"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["aiConsent.detailsList"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'DeepSeek'")).count > 0,
                      "Details names the providers")

        app.buttons["aiConsent.notNow"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertFalse(fieldValueContains("(expanded draft -- mock)", timeout: 2), "Not now: no rewrite")
        XCTAssertTrue(consentLine.waitForExistence(timeout: 3), "the rewrite row says why")
        XCTAssertEqual(aiSent, 0, "Not now: nothing was sent")

        // Not now is not remembered: the next AI action asks again.
        app.buttons["style.ai.expand"].tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        app.buttons["aiConsent.continue"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(fieldValueContains("(expanded draft -- mock)"), "Continue: the action goes on")
        XCTAssertEqual(aiSent, 1)

        app.buttons["style.ai.clean"].tap()
        XCTAssertFalse(sheet.waitForExistence(timeout: 2), "never asked again")
        XCTAssertEqual(aiSent, 2, "Clean went out without asking")

        // Kept across a relaunch.
        app.terminate()
        launch(asking: true, keep: true)
        startWriting("tea")
        app.buttons["style.ai"].tap()
        app.buttons["style.ai.expand"].tap()
        XCTAssertTrue(fieldValueContains("(expanded draft -- mock)"))
        XCTAssertFalse(sheet.exists)
    }

    func testAFirstSaveAsksOnceAndNotNowLeavesTheStarNeutral() {
        launch(asking: true)
        savePage("A happy picnic")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "a Save asks once the editor is gone")
        app.buttons["aiConsent.notNow"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))

        savePage("A sunny walk")
        XCTAssertFalse(sheet.waitForExistence(timeout: 3), "a Save asks once a launch")

        openJar()
        let star = app.buttons["jar.star.A happy picnic"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        waitForLabel(star, "A happy picnic, mood off")
        XCTAssertEqual(aiSent, 0, "no mood was asked")
    }

    func testContinueAfterASaveReadsTheMood() {
        launch(asking: true)
        savePage("A happy picnic")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        app.buttons["aiConsent.continue"].tap()
        openJar()
        let star = app.buttons["jar.star.A happy picnic"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        waitForLabel(star, "A happy picnic, Joyful")
        // The jar also reads the seeded pages it shows.
        XCTAssertGreaterThanOrEqual(aiSent, 1)
    }

    func testMoodSwitchOffSendsNoMoodAndOnReadsIt() {
        launch(asking: false)
        openSettings()
        let mood = app.switches["settings.moodFromWords"]
        XCTAssertTrue(mood.waitForExistence(timeout: 5))
        XCTAssertEqual(mood.value as? String, "1", "on by default after consent")
        mood.tap()
        XCTAssertTrue(waitForValue(mood, "0"))
        backHome()

        savePage("A happy picnic")
        openJar()
        let star = app.buttons["jar.star.A happy picnic"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        // Room for a mood request, if one were going out.
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "no mood")], timeout: 2)
        waitForLabel(star, "A happy picnic, mood off")
        XCTAssertEqual(aiSent, 0, "mood off: no mood request after the Save")

        // On again: the saved page is read.
        app.buttons["Home"].tap()
        openSettings()
        mood.tap()
        XCTAssertTrue(waitForValue(mood, "1"))
        backHome()
        openJar()
        waitForLabel(star, "A happy picnic, Joyful")
        XCTAssertGreaterThanOrEqual(aiSent, 1)
    }

    func testDictationAsksBeforeTheMicStarts() {
        launch(asking: true)
        startWriting("note")
        let mic = app.buttons["style.mic"]
        mic.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "asked before recording")
        XCTAssertEqual(probeMax("micLive"), 0, "no mic while the sheet is up")
        app.buttons["aiConsent.notNow"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(consentLine.waitForExistence(timeout: 3), "the strip says why")
        XCTAssertEqual(probeMax("micLive"), 0, "Not now: the mic never started")
        XCTAssertNotEqual(mic.value as? String, "Listening...")

        mic.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        app.buttons["aiConsent.continue"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertEqual(probeMax("micLive"), 0, "the sheet ended the press: no take yet")
        // Granted: the next tap records, without asking.
        mic.tap()
        expectation(for: NSPredicate(format: "value == %@", "Listening..."), evaluatedWith: mic)
        waitForExpectations(timeout: 5)
    }

    func testNotNowOnAStickerSaysWhy() {
        launch(asking: true)
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.sticker"].waitForExistence(timeout: 5))
        app.buttons["mode.sticker"].tap()
        let prompt = app.textFields["sticker.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("a cat")
        app.buttons["sticker.generate.run"].tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        app.buttons["aiConsent.notNow"].tap()
        XCTAssertTrue(consentLine.waitForExistence(timeout: 5), "the panel says why")
        XCTAssertEqual(aiSent, 0)
    }

    func testWithdrawShowsTheSheetAgain() {
        launch(asking: false)
        openSettings()
        let withdraw = app.buttons["settings.aiWithdraw"]
        XCTAssertTrue(withdraw.waitForExistence(timeout: 5))
        withdraw.tap()
        XCTAssertTrue(app.buttons["settings.aiAllow"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["settings.moodFromWords"].value as? String, "0", "no moods without consent")
        backHome()

        startWriting("noodle shop")
        app.buttons["style.ai"].tap()
        app.buttons["style.ai.expand"].tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "withdrawn: the next AI action asks again")
        app.buttons["aiConsent.notNow"].tap()
        XCTAssertFalse(fieldValueContains("(expanded draft -- mock)", timeout: 2))
        XCTAssertEqual(aiSent, 0)
    }
}
