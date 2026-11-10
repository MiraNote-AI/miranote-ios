import XCTest

/// The review of iOS#172: a TestFlight install shows the photo trigger only
/// once the tester turns it on in Settings, after a confirmation that says
/// what is uploaded. `-TRIGGER-INSTALL` makes this development build answer
/// as that install would; the synthetic library stands in for the photos.
final class PhotoTriggerOptInUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: Helpers

    /// `-TRIGGER-NO-SCHEDULE`: nothing plans itself, so no run slows the test.
    private func launch(install: String?, keep: Bool = false) {
        app.launchArguments = ["-UITEST", "-UITEST-TRIGGER", "-TRIGGER-NO-SCHEDULE"]
            + (install.map { ["-TRIGGER-INSTALL", $0] } ?? []) + (keep ? ["-KEEP_SETTINGS"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 8))
    }

    private var debugCard: XCUIElement { app.switches["trigger.fakeAI"] }
    private var optIn: XCUIElement { app.switches["settings.photoTrigger"] }

    private func openSettings() {
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.buttons["settings.appearance"].waitForExistence(timeout: 5))
    }

    private func backHome() {
        app.buttons["settings.back"].tap()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
    }

    /// Waits up to `timeout` for `element` to be gone.
    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Waits up to `timeout` for the switch `element` to read `value`.
    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 5) -> Bool {
        let reads = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [reads], timeout: timeout) == .completed
    }

    // MARK: Tests

    func testDevelopmentBuildHasNoSwitchAndShowsTheCard() {
        launch(install: nil)
        XCTAssertTrue(debugCard.waitForExistence(timeout: 5), "development builds are unchanged")
        openSettings()
        XCTAssertFalse(optIn.exists)
    }

    func testAppStoreInstallHasNeitherSwitchNorCard() {
        launch(install: "appstore")
        XCTAssertFalse(debugCard.waitForExistence(timeout: 3))
        openSettings()
        XCTAssertFalse(optIn.exists)
    }

    func testTestFlightStartsOffAndCancelKeepsItOff() {
        launch(install: "testflight")
        XCTAssertFalse(debugCard.waitForExistence(timeout: 3), "nothing shows before the tester turns it on")
        openSettings()
        XCTAssertTrue(optIn.waitForExistence(timeout: 5))
        XCTAssertEqual(optIn.value as? String, "0")
        optIn.tap()
        let alert = app.alerts["Turn on photo memories?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS 'AI service'")).count > 0,
                      "the confirmation says the photos go to an AI service")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(waitForAbsence(alert))
        XCTAssertEqual(optIn.value as? String, "0", "cancelled: still off")
        backHome()
        XCTAssertFalse(debugCard.exists)
    }

    func testTestFlightTurnsOnAfterConfirmingAndOffAtOnce() {
        launch(install: "testflight")
        openSettings()
        optIn.tap()
        let turnOn = app.alerts["Turn on photo memories?"].buttons["Turn On"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: 5))
        turnOn.tap()
        XCTAssertTrue(waitForValue(optIn, "1"))
        backHome()
        XCTAssertTrue(debugCard.waitForExistence(timeout: 5), "on: the card shows without a relaunch")

        // Kept across a relaunch.
        app.terminate()
        launch(install: "testflight", keep: true)
        XCTAssertTrue(debugCard.waitForExistence(timeout: 5), "still on after a relaunch")

        openSettings()
        optIn.tap()
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 1), "turning off asks nothing")
        XCTAssertTrue(waitForValue(optIn, "0"))
        backHome()
        XCTAssertTrue(waitForAbsence(debugCard), "off: the card goes at once")
    }
}
