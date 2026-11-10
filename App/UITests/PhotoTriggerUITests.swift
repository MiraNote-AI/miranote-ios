import XCTest

/// The photo trigger end to end on the synthetic library (`-UITEST-TRIGGER`:
/// painted colour blocks, no personal photos): Home's debug entry, its
/// progress, opening a push (as a tap would, through the launch router),
/// the peak-first story, the ending, the menu and the canvas draft.
///
/// `TRIGGER_SHOTS=<dir>` (TEST_RUNNER_TRIGGER_SHOTS for xcodebuild) saves
/// screenshots of each step there, the gather as a burst.
final class PhotoTriggerUITests: XCTestCase {
    var app: XCUIApplication!
    private var shotDirectory: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
        shotDirectory = ProcessInfo.processInfo.environment["TRIGGER_SHOTS"].map { URL(fileURLWithPath: $0) }
        app = XCUIApplication()
    }

    // MARK: Helpers

    /// `-TRIGGER-NO-SCHEDULE`: nothing plans itself on launch, so every group
    /// is outside the schedule for the debug buttons.
    func launch(_ extra: [String] = [], keep: Bool = false) {
        app.launchArguments = ["-UITEST", "-UITEST-TRIGGER", "-TRIGGER-NO-SCHEDULE"]
            + (keep ? ["-KEEP_SETTINGS"] : []) + extra
        app.launch()
    }

    /// Scrolls Home down to the debug entry's button `id`.
    @discardableResult
    func entryButton(_ id: String) -> XCUIElement {
        let button = app.buttons[id]
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        for _ in 0..<6 where !button.isHittable {
            app.swipeUp()
        }
        return button
    }

    func progressLine(_ prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Presses a push button and waits for "Scheduled".
    func pushAndWait(_ id: String = "trigger.tryOutside") {
        entryButton(id).tap()
        XCTAssertTrue(progressLine("Scheduled").waitForExistence(timeout: 20), "the push was scheduled")
    }

    /// Relaunches as a tap on the newest push would.
    func openLatestPush(_ extra: [String] = []) {
        app.terminate()
        launch(["-TRIGGER-OPEN-PUSH", "latest"] + extra, keep: true)
    }

    func photo(_ number: Int, of count: Int) -> XCUIElement {
        app.descendants(matching: .any)["Photo \(number) of \(count)"].firstMatch
    }

    /// Steps through the story to the ending's button.
    func skipToEnding(photos count: Int) -> XCUIElement {
        XCTAssertTrue(photo(1, of: count).waitForExistence(timeout: 8))
        let right = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        for _ in 0..<count { right.tap() }
        let keep = app.buttons["trigger.keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 6))
        Thread.sleep(forTimeInterval: 1.2)
        return keep
    }

    /// The fake AI's date label: group A, three days ago ("10.28").
    var groupADate: String {
        let day = Calendar.current.date(byAdding: .day, value: -3, to: .now)!
        let parts = Calendar.current.dateComponents([.month, .day], from: day)
        return String(format: "%d.%02d", parts.month!, parts.day!)
    }

    func shot(_ name: String) {
        guard let shotDirectory else { return }
        try? FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: shotDirectory.appendingPathComponent("\(name).png"))
    }

    // MARK: Debug entry (C2, C3, C5)

    func testDebugEntryHasTwoButtonsAndFakeAIToggle() {
        launch()
        XCTAssertTrue(entryButton("trigger.preview").exists)
        XCTAssertTrue(app.buttons["trigger.tryOutside"].exists)
        let toggle = app.switches["trigger.fakeAI"]
        XCTAssertTrue(toggle.exists)
        XCTAssertEqual(toggle.value as? String, "0", "off unless switched on")
        shot("c2-entry")
    }

    func testProgressShowsEachStepInOrder() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        let preparing = progressLine("Preparing")
        let looking = progressLine("Looking at photos 19/19")
        let asking = progressLine("Asking the AI... (rank 1: \(groupADate), 10 photos)")
        let scheduled = progressLine("Scheduled, the push comes in 10 s (rank 1, score")
        for line in [preparing, looking, asking, scheduled] { XCTAssertTrue(line.exists, line.debugDescription) }
        XCTAssertLessThan(preparing.frame.minY, looking.frame.minY)
        XCTAssertLessThan(looking.frame.minY, asking.frame.minY)
        XCTAssertLessThan(asking.frame.minY, scheduled.frame.minY)
        shot("c3-progress")
    }

    func testTryOutsideWalksTheRanksAndWraps() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait("trigger.tryOutside")
        XCTAssertTrue(progressLine("Scheduled, the push comes in 10 s (rank 1").exists)
        // One group per press; past the last, the walk starts again from the top.
        var wrapped = false
        for _ in 0..<5 where !wrapped {
            app.buttons["trigger.tryOutside"].tap()
            wrapped = progressLine("That was the last group").waitForExistence(timeout: 20)
        }
        XCTAssertTrue(wrapped, "the walk wraps with a notice")
        XCTAssertTrue(progressLine("Scheduled, the push comes in 10 s (rank 1").waitForExistence(timeout: 20))
        shot("c2-wrapped")
    }

    // MARK: Preview of the schedule

    func testPreviewWithNothingScheduledSaysSo() {
        launch()
        entryButton("trigger.preview").tap()
        XCTAssertTrue(app.staticTexts["Nothing is scheduled right now"].waitForExistence(timeout: 10))
        shot("a1-nothing-scheduled")
    }

    /// Without `-TRIGGER-NO-SCHEDULE` the launch plans the nights by itself;
    /// the preview then sends a copy of one of them.
    func testPreviewSendsAScheduledPush() {
        app.launchArguments = ["-UITEST", "-UITEST-TRIGGER"]
        app.launch()
        let sent = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'The push for'")).firstMatch
        let nothing = app.staticTexts["Nothing is scheduled right now"]
        for _ in 0..<10 where !sent.exists {
            entryButton("trigger.preview").tap()
            _ = sent.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(sent.exists, "the launch scheduled something to preview")
        XCTAssertFalse(nothing.exists)
        shot("a1-preview")
    }

    func testRejectedGroupsStopAfterThree() {
        launch(["-TRIGGER-REJECT"])
        entryButton("trigger.tryOutside").tap()
        XCTAssertTrue(progressLine("Tried 3 groups and none passed").waitForExistence(timeout: 20))
        XCTAssertTrue(progressLine("Rank 1 did not pass").exists)
        XCTAssertTrue(progressLine("Rank 2 did not pass").exists)
        shot("c4-three-failed")
    }

    /// D2b: sent away while the AI works, the press picks its job up on
    /// return and still schedules the push.
    func testLeavingWhileWaitingStillSchedules() {
        launch(["-TRIGGER-SLOW-AI", "25"])
        entryButton("trigger.tryOutside").tap()
        XCTAssertTrue(progressLine("Asking the AI").waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Please stay here, about a minute"].exists)
        shot("d2b-asking")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 30)
        app.activate()
        XCTAssertTrue(progressLine("Scheduled").waitForExistence(timeout: 30), "the same job finished after the return")
        XCTAssertFalse(progressLine("Cannot reach the backend").exists)
        shot("d2b-scheduled")
    }

    // MARK: Failures (G1, G3, G4, G5)

    func testBackendDownSaysSo() {
        launch(["-TRIGGER-BACKEND-DOWN"])
        entryButton("trigger.tryOutside").tap()
        XCTAssertTrue(progressLine("Cannot reach the backend").waitForExistence(timeout: 20))
        shot("g1-backend-down")
    }

    func testEmptyLibraryFindsNoGroup() {
        launch(["-TRIGGER-EMPTY", "-TRIGGER-FAKE-AI"])
        entryButton("trigger.tryOutside").tap()
        XCTAssertTrue(progressLine("No suitable group in the last 60 days").waitForExistence(timeout: 20))
        shot("g3-empty")
    }

    func testPermissionsOffOfferSettings() {
        launch(["-TRIGGER-NOTIFICATIONS-OFF"])
        entryButton("trigger.tryOutside").tap()
        XCTAssertTrue(progressLine("Notifications are off").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["trigger.openSettings"].exists)
        shot("g4-notifications-off")
        app.terminate()
        launch(["-TRIGGER-PHOTOS-DENIED"])
        entryButton("trigger.tryOutside").tap()
        XCTAssertTrue(progressLine("Photo library access is needed").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["trigger.openSettings"].exists)
        shot("g4-photos-denied")
    }

    func testLimitedLibraryRunsWithANote() {
        launch(["-PHOTOS-LIMITED", "-TRIGGER-FAKE-AI"])
        pushAndWait()
        XCTAssertTrue(progressLine("Only some photos are visible").exists)
        shot("g5-limited")
    }
}
