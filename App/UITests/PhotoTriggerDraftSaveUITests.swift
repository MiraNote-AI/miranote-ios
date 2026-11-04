import XCTest

/// A page drafted from a push is kept only if touched or finished (A3).
extension PhotoTriggerUITests {
    /// Opens the newest push's story to its canvas draft.
    private func openDraft() {
        launch()
        pushAndWait()
        openLatestPush()
        skipToEnding(photos: 8).tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10), "the canvas opened")
    }

    private var ledgerText: String {
        app.descendants(matching: .any)["debug.triggerLedger"].firstMatch.label
    }

    private func waitForLedger(made: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let probe = app.descendants(matching: .any)["debug.triggerLedger"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 8), file: file, line: line)
        let predicate = NSPredicate(format: made ? "label CONTAINS ':made'" : "NOT (label CONTAINS ':made')")
        expectation(for: predicate, evaluatedWith: probe)
        waitForExpectations(timeout: 8)
    }

    private func assertNoPageOnHome(file: StaticString = #filePath, line: UInt = #line) {
        let log = app.buttons["collection.Daily Log"]
        XCTAssertTrue(log.waitForExistence(timeout: 6), file: file, line: line)
        log.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.buttons["note.\(groupADate)"].exists, "no page was filed", file: file, line: line)
    }

    func testUntouchedPushDraftLeavesNoPage() {
        openDraft()
        app.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 6))
        waitForLedger(made: false)
        assertNoPageOnHome()
    }

    func testUntouchedPushDraftBackgroundedAndKilledLeavesNoPage() {
        openDraft()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.terminate()
        launch(keep: true)
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        waitForLedger(made: false)
        assertNoPageOnHome()
    }

    func testPushDraftDoneWithoutWritingIsFiled() {
        openDraft()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 6))
        waitForLedger(made: true)
        let log = app.buttons["collection.Daily Log"]
        XCTAssertTrue(log.waitForExistence(timeout: 4))
        log.tap()
        XCTAssertTrue(app.buttons["note.\(groupADate)"].waitForExistence(timeout: 5))
    }

    func testEditedPushDraftIsFiledOnBack() {
        openDraft()
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("my own words")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.staticTexts["my own words"].waitForExistence(timeout: 5))
        app.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 6))
        waitForLedger(made: true)
        let log = app.buttons["collection.Daily Log"]
        XCTAssertTrue(log.waitForExistence(timeout: 4))
        log.tap()
        XCTAssertTrue(app.buttons["note.\(groupADate)"].waitForExistence(timeout: 5))
    }
}
