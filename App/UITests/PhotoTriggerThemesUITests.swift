import XCTest

/// The debug page "Themes" (spec 6.10, acceptance F1-F3) on the synthetic
/// library (`-UITEST-TRIGGER`: painted blocks, no personal photos). On
/// launch the themes are found and claimed on a second run
/// (`-TRIGGER-FIND-THEMES`): two big themes, home dinner (8 days) and the
/// morning light (6 days), and one small theme, weekday dinner.
/// `-TRIGGER-FLAG-THEME <share>` then sets home dinner's claim to that
/// share (flagged by the claim's rule), as an old theme partly gone from
/// its pile would have it. Chinese is written as escapes (org rule 3).
///
/// `TRIGGER_SHOTS=<dir>` (TEST_RUNNER_TRIGGER_SHOTS for xcodebuild) saves
/// screenshots there.
final class PhotoTriggerThemesUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shotDirectory: URL?

    /// Home dinner, weekday dinner, the morning light outside the window.
    private let dinner = "\u{5BB6}\u{91CC}\u{7684}\u{665A}\u{996D}"
    private let weekdayDinner = "\u{5DE5}\u{4F5C}\u{65E5}\u{665A}\u{996D}"
    private let morning = "\u{7A97}\u{5916}\u{7684}\u{6668}\u{5149}"
    /// The scripted backend's "where" line: "mostly at one place".
    private let whereLine = "\u{4E3B}\u{8981}\u{5728}\u{540C}\u{4E00}\u{4E2A}\u{5730}\u{65B9}"

    override func setUpWithError() throws {
        continueAfterFailure = false
        shotDirectory = ProcessInfo.processInfo.environment["TRIGGER_SHOTS"].map { URL(fileURLWithPath: $0) }
        app = XCUIApplication()
    }

    // MARK: F1 -- what the page shows

    func testThemesPageListsPilesAndThemes() {
        openThemes()
        let runs = rows("themes.run")
        XCTAssertGreaterThanOrEqual(runs.count, 2, "found, then claimed")
        XCTAssertTrue(runs.firstMatch.label.contains("Moments 14, piles 2"), runs.firstMatch.label)
        XCTAssertTrue(runs.firstMatch.label.contains("Checkup "), runs.firstMatch.label)
        XCTAssertTrue(runs.firstMatch.label.contains("Memory "), runs.firstMatch.label)

        let piles = rows("themes.pile")
        XCTAssertEqual(piles.count, 2)
        XCTAssertTrue(piles.element(boundBy: 0).label.hasPrefix("Pile 1: 8 days, 8 moments"),
                      piles.element(boundBy: 0).label)
        XCTAssertTrue(piles.element(boundBy: 1).label.hasPrefix("Pile 2: 6 days, 6 moments"),
                      piles.element(boundBy: 1).label)

        XCTAssertEqual(rows("themes.theme").count, 3)
        for name in [dinner, weekdayDinner, morning] {
            XCTAssertTrue(text(name).exists, name)
        }
        let follows = app.staticTexts.matching(identifier: "themes.follow")
        XCTAssertEqual(follows.count, 2, "big themes only")
        XCTAssertEqual(follows.element(boundBy: 0).label, "Follows pile 1, 100%")
        XCTAssertEqual(follows.element(boundBy: 1).label, "Follows pile 2, 100%")
        XCTAssertTrue(text("Photos 8, days 8").exists)
        XCTAssertTrue(text("Photos 6, days 6").exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'Cooldown: -'")).count, 3)
        shot("themes-page")

        // The round answers, raw, newest first.
        app.buttons.matching(identifier: "themes.details").element(boundBy: 0).tap()
        let answer = rows("themes.round").firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 4))
        XCTAssertTrue(answer.label.contains("round1"), answer.label)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'pile_name'")).firstMatch.exists,
                      "the raw reply")
        shot("themes-detail")
    }

    /// Just under a half: flagged, and never shown as "50%".
    func testFlaggedRatioShowsYellow() {
        openThemes(["-TRIGGER-FLAG-THEME", "0.499"], until: "Follows pile 1, 49.9%")
        let follows = app.staticTexts.matching(identifier: "themes.follow")
        XCTAssertEqual(follows.element(boundBy: 0).value as? String, "flagged")
        XCTAssertNotEqual(follows.element(boundBy: 1).value as? String, "flagged", "100% is not flagged")
        shot("themes-flagged")
    }

    /// Exactly a half follows unflagged (spec C2): no yellow.
    func testHalfRatioIsNotYellow() {
        openThemes(["-TRIGGER-FLAG-THEME", "0.5"], until: "Follows pile 1, 50%")
        let follows = app.staticTexts.matching(identifier: "themes.follow")
        XCTAssertNotEqual(follows.element(boundBy: 0).value as? String, "flagged")
        shot("themes-half")
    }

    func testGroupNameBesideWhereLine() {
        openThemes()
        let lines = rows("themes.groupWhere")
        XCTAssertEqual(lines.count, 1, "one line per small theme")
        let line = lines.firstMatch
        XCTAssertTrue(line.label.contains("Qwen: \(weekdayDinner)"), line.label)
        XCTAssertTrue(line.label.contains("Phone: \(whereLine)"), line.label)
        shot("themes-group-where")
    }

    // MARK: F2 -- test-push a theme

    /// The push is handed to the notification centre to fire 10 s later,
    /// as a debug push: the ledger row says debug. (A delivered system
    /// notification is a device check: the synthetic centre never shows one.)
    func testTestPushSchedulesDebugPush() {
        openThemes()
        let button = app.buttons.matching(identifier: "themes.tryTheme").element(boundBy: 0)
        let pressed = Date().timeIntervalSince1970
        button.tap()
        let scheduled = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Scheduled, the push comes in 10 s")).firstMatch
        XCTAssertTrue(scheduled.waitForExistence(timeout: 40))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Writing the push for \(dinner)")).firstMatch.exists)
        shot("themes-test-push")

        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let ledger = app.descendants(matching: .any)["debug.triggerLedger"].firstMatch
        XCTAssertTrue(ledger.waitForExistence(timeout: 8))
        let deadline = Date().addingTimeInterval(8)
        while !ledger.label.hasSuffix(":debug"), Date() < deadline { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(ledger.label.components(separatedBy: ";").count, 1, ledger.label)
        XCTAssertTrue(ledger.label.hasSuffix(":none:debug"), ledger.label)

        // The same push, handed over with a trigger 10 s out.
        let pushId = ledger.label.replacingOccurrences(of: ":none:debug", with: "")
        let handed = app.descendants(matching: .any)["debug.triggerNotifier"].firstMatch
        XCTAssertTrue(handed.waitForExistence(timeout: 4))
        let requests = handed.label.components(separatedBy: ";")
        XCTAssertEqual(requests.count, 1, handed.label)
        let parts = requests[0].components(separatedBy: "@")
        XCTAssertEqual(parts.first, "pt.\(pushId):10s", handed.label)
        let at = Double(parts.last ?? "") ?? 0
        XCTAssertGreaterThan(at, pressed, "handed over after the press")
        print("theme push handed over \(at - pressed) s after the press")
    }

    // MARK: F3 -- blocked themes

    func testBlockedThemeCanBeCleared() {
        openThemes()
        XCTAssertTrue(text("No theme is blocked").exists)
        app.buttons.matching(identifier: "themes.details").element(boundBy: 2).tap()
        let block = app.buttons["themes.block"]
        XCTAssertTrue(block.waitForExistence(timeout: 4))
        block.tap()
        XCTAssertTrue(app.buttons["themes.unblock"].waitForExistence(timeout: 6), "the block took")
        app.navigationBars.buttons.firstMatch.tap()

        let clear = app.buttons.matching(identifier: "themes.clear")
        XCTAssertTrue(clear.firstMatch.waitForExistence(timeout: 6))
        XCTAssertEqual(clear.count, 1)
        let row = rows("themes.blocked").firstMatch
        XCTAssertTrue(row.label.contains(morning), row.label)
        XCTAssertTrue(text("Status: blocked").exists)
        scrollTo(clear.firstMatch)
        shot("themes-blocked")

        clear.firstMatch.tap()
        XCTAssertTrue(text("No theme is blocked").waitForExistence(timeout: 6))
        XCTAssertFalse(text("Status: blocked").exists)
        shot("themes-cleared")
    }

    // MARK: Helpers

    /// Opens Home's debug screen, then "Themes", and pulls to refresh until
    /// the launch's theme runs are on the page.
    private func openThemes(_ extra: [String] = [], until line: String = "Follows pile 2, 100%") {
        app.launchArguments = ["-UITEST", "-UITEST-TRIGGER", "-TRIGGER-NO-SCHEDULE", "-TRIGGER-FIND-THEMES"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        let details = app.buttons["trigger.allDetails"]
        scrollTo(details)
        details.tap()
        let link = app.buttons["debug.section.themes"]
        XCTAssertTrue(link.waitForExistence(timeout: 6))
        scrollTo(link)
        link.tap()
        XCTAssertTrue(app.descendants(matching: .any)["themes.screen"].firstMatch.waitForExistence(timeout: 6))
        let ready = text(line)
        let deadline = Date().addingTimeInterval(40)
        while !ready.exists, Date() < deadline {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(ready.exists, "the themes were found and claimed")
    }

    private func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func rows(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
    }

    private func shot(_ name: String) {
        guard let shotDirectory else { return }
        try? FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: shotDirectory.appendingPathComponent("\(name).png"))
    }
}
