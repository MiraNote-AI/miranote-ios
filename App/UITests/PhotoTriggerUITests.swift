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

    func launch(_ extra: [String] = [], keep: Bool = false) {
        app.launchArguments = ["-UITEST", "-UITEST-TRIGGER"] + (keep ? ["-KEEP_SETTINGS"] : []) + extra
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
    func pushAndWait(_ id: String = "trigger.pushTop") {
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
        XCTAssertTrue(entryButton("trigger.pushTop").exists)
        XCTAssertTrue(app.buttons["trigger.pushNext"].exists)
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

    func testPushNextWalksTheRanksAndWraps() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait("trigger.pushNext")
        XCTAssertTrue(progressLine("Scheduled, the push comes in 10 s (rank 1").exists)
        for rank in [2, 3] {
            app.buttons["trigger.pushNext"].tap()
            XCTAssertTrue(progressLine("Scheduled, the push comes in 10 s (rank \(rank)").waitForExistence(timeout: 20))
        }
        app.buttons["trigger.pushNext"].tap()
        XCTAssertTrue(progressLine("That was the last group").waitForExistence(timeout: 20))
        XCTAssertTrue(progressLine("Scheduled, the push comes in 10 s (rank 1").waitForExistence(timeout: 20))
        shot("c2-wrapped")
    }

    func testRejectedGroupsStopAfterThree() {
        launch(["-TRIGGER-REJECT"])
        entryButton("trigger.pushTop").tap()
        XCTAssertTrue(progressLine("Tried 3 groups and none passed").waitForExistence(timeout: 20))
        XCTAssertTrue(progressLine("Rank 1 did not pass").exists)
        XCTAssertTrue(progressLine("Rank 2 did not pass").exists)
        shot("c4-three-failed")
    }

    // MARK: Failures (G1, G3, G4, G5)

    func testBackendDownSaysSo() {
        launch(["-TRIGGER-BACKEND-DOWN"])
        entryButton("trigger.pushTop").tap()
        XCTAssertTrue(progressLine("Cannot reach the backend").waitForExistence(timeout: 20))
        shot("g1-backend-down")
    }

    func testEmptyLibraryFindsNoGroup() {
        launch(["-TRIGGER-EMPTY", "-TRIGGER-FAKE-AI"])
        entryButton("trigger.pushTop").tap()
        XCTAssertTrue(progressLine("No suitable group in the last 60 days").waitForExistence(timeout: 20))
        shot("g3-empty")
    }

    func testPermissionsOffOfferSettings() {
        launch(["-TRIGGER-NOTIFICATIONS-OFF"])
        entryButton("trigger.pushTop").tap()
        XCTAssertTrue(progressLine("Notifications are off").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["trigger.openSettings"].exists)
        shot("g4-notifications-off")
        app.terminate()
        launch(["-TRIGGER-PHOTOS-DENIED"])
        entryButton("trigger.pushTop").tap()
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
