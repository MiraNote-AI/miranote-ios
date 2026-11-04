import XCTest

/// Phase 2, A1: the scheduler starts by itself when the app comes to the
/// front -- the first-launch prompts come in order, and Home shows no
/// progress for any of it.
final class PhotoTriggerLifecycleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Photos first, then notifications (G5). The synthetic library and
    /// scripted backend stay; only the two system prompts are real
    /// (`-TRIGGER-REAL-PERMISSIONS`).
    func testFirstLaunchAsksPhotosThenNotifications() {
        app.resetAuthorizationStatus(for: .photos)
        app.launchArguments = ["-UITEST", "-UITEST-TRIGGER", "-TRIGGER-REAL-PERMISSIONS"]
        app.launch()
        // The simulator may speak Chinese: match both languages.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let photosAlert = springboard.alerts.firstMatch
        XCTAssertTrue(photosAlert.waitForExistence(timeout: 15), "the first prompt appears")
        let first = photosAlert.label
        XCTAssertTrue(mentions(first, ["photo", "\u{7167}\u{7247}"]), "Photos comes first: \(first)")
        let full = ["Allow Full Access", "Allow Access to All Photos", "\u{5B8C}\u{5168}\u{8BBF}\u{95EE}"]
        tapAllow(in: photosAlert, titles: full + ["\u{6240}\u{6709}\u{7167}\u{7247}"])

        // The notification prompt is asked once per install: when an earlier
        // run already answered it, nothing more comes and that is correct.
        let next = springboard.alerts.firstMatch
        if next.waitForExistence(timeout: 8) {
            XCTAssertFalse(mentions(next.label, ["photo", "\u{7167}\u{7247}"]), "Photos is not asked twice")
            XCTAssertTrue(mentions(next.label, ["notification", "\u{901A}\u{77E5}"]), next.label)
            tapAllow(in: next, titles: ["Allow", "\u{5141}\u{8BB8}"])
        }
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8), "Home is there")
    }

    func testHomeShowsNoProgressOnFirstLaunch() {
        app.launchArguments = ["-UITEST", "-UITEST-TRIGGER"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        // Let the first run plan its nights.
        Thread.sleep(forTimeInterval: 6)
        for _ in 0..<6 where !app.buttons["trigger.preview"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["trigger.preview"].exists, "the debug entry shows")
        XCTAssertFalse(app.otherElements["trigger.progress"].exists, "no progress on Home (G7)")
        XCTAssertFalse(app.staticTexts["Preparing..."].exists)
        let counting = NSPredicate(format: "label BEGINSWITH 'Looking at photos'")
        XCTAssertFalse(app.staticTexts.matching(counting).firstMatch.exists)
    }

    private func mentions(_ label: String, _ words: [String]) -> Bool {
        words.contains { label.localizedCaseInsensitiveContains($0) }
    }

    private func tapAllow(in alert: XCUIElement, titles: [String]) {
        let button = alert.buttons.allElementsBoundByIndex.first { button in
            titles.contains { button.label.localizedCaseInsensitiveContains($0) }
        }
        XCTAssertNotNil(button, "an allow button among \(alert.buttons.allElementsBoundByIndex.map(\.label))")
        button?.tap()
    }
}
