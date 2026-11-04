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

    override func tearDownWithError() throws {
        // Never leave a system alert up for the next test (a combined run).
        dismissSystemAlerts()
        app.terminate()
    }

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    // The simulator may speak Chinese: match both languages.
    private let photoWords = ["photo", "\u{7167}\u{7247}"]
    private let notificationWords = ["notification", "\u{901A}\u{77E5}"]
    private let photosAllow = ["Allow Full Access", "Allow Access to All Photos", "\u{5B8C}\u{5168}\u{8BBF}\u{95EE}",
                               "\u{6240}\u{6709}\u{7167}\u{7247}"]
    private let notificationsAllow = ["Allow", "\u{5141}\u{8BB8}"]

    /// Photos first, then notifications (G5). The synthetic library and
    /// scripted backend stay; only the two system prompts are real
    /// (`-TRIGGER-REAL-PERMISSIONS`).
    ///
    /// Photos is reset before launch, so its prompt always comes. The
    /// notification prompt is asked once per install and cannot be reset
    /// from a test: it shows unless an earlier run on this simulator
    /// already answered it (uninstall the app, `xcrun simctl uninstall
    /// <device> ai.miranote.app`, to see it again). So it is checked only
    /// when it shows: then it must come after Photos.
    ///
    /// Every alert is answered as it comes, each one waited out before the
    /// next is looked for, and none is left up at the end (tearDown).
    func testFirstLaunchAsksPhotosThenNotifications() {
        app.resetAuthorizationStatus(for: .photos)
        app.launchArguments = ["-UITEST", "-UITEST-TRIGGER", "-TRIGGER-REAL-PERMISSIONS"]
        app.launch()
        let seen = answerAlerts(first: 15, quiet: 6)
        XCTAssertFalse(seen.isEmpty, "the first prompt appears")
        XCTAssertTrue(mentions(seen.first ?? "", photoWords), "Photos comes first: \(seen)")
        XCTAssertEqual(seen.filter { mentions($0, photoWords) }.count, 1, "Photos is asked once: \(seen)")
        XCTAssertLessThanOrEqual(seen.count, 2, "nothing else is asked: \(seen)")
        if seen.count == 2 {
            XCTAssertTrue(mentions(seen[1], notificationWords), "then notifications: \(seen)")
        }
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "no alert is left up")
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

    /// Answers each system alert as it shows -- waiting `first` seconds for
    /// the first, then `quiet` for each next -- and returns their labels in
    /// order. Each is gone (or replaced) before the next is looked for, so
    /// one alert is never counted twice.
    private func answerAlerts(first: TimeInterval, quiet: TimeInterval) -> [String] {
        var seen: [String] = []
        while seen.count < 4 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: seen.isEmpty ? first : quiet) else { break }
            let label = alert.label
            seen.append(label)
            let titles = mentions(label, photoWords) ? photosAllow : notificationsAllow
            guard tapAllow(in: alert, titles: titles) else { break }
            XCTAssertTrue(waitUntilGone(alert, label: label), "the alert went away: \(label)")
        }
        return seen
    }

    /// The allow button: a title exactly, else one containing a title but
    /// not a refusal ("Don't Allow" contains "Allow").
    private func allowButton(in alert: XCUIElement, titles: [String]) -> XCUIElement? {
        let buttons = alert.buttons.allElementsBoundByIndex
        let refusals = ["Don\u{2019}t", "Don't", "\u{4E0D}"]
        return buttons.first { titles.contains($0.label) } ?? buttons.first { button in
            titles.contains { button.label.localizedCaseInsensitiveContains($0) }
                && !refusals.contains { button.label.contains($0) }
        }
    }

    /// Taps the allow button; false (and a failure) when there is none.
    @discardableResult
    private func tapAllow(in alert: XCUIElement, titles: [String]) -> Bool {
        let buttons = alert.buttons.allElementsBoundByIndex
        guard let button = allowButton(in: alert, titles: titles) else {
            XCTFail("an allow button among \(buttons.map(\.label))")
            return false
        }
        button.tap()
        return true
    }

    /// True once no alert is up, or a different one is.
    private func waitUntilGone(_ alert: XCUIElement, label: String, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !alert.exists || alert.label != label { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    /// Answers whatever system alert is still up (allow when it can, else
    /// its last button), so the next test starts clean.
    private func dismissSystemAlerts() {
        for _ in 0..<4 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { return }
            let allow = allowButton(in: alert, titles: photosAllow + notificationsAllow)
            guard let button = allow ?? alert.buttons.allElementsBoundByIndex.last else { return }
            let label = alert.label
            button.tap()
            _ = waitUntilGone(alert, label: label, timeout: 3)
        }
    }
}
