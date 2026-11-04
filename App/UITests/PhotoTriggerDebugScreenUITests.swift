import XCTest

/// The tester-only debug screen (phase 2, task A4), on the synthetic library
/// (`-UITEST-TRIGGER`: painted colour blocks, no personal photos). Each
/// section is saved as an XCTAttachment and, when the folder exists, as a
/// PNG under the scratchpad.
final class PhotoTriggerDebugScreenUITests: XCTestCase {
    var app: XCUIApplication!

    private static let shotFolder = URL(fileURLWithPath:
        "/private/tmp/claude-501/-Users-zhizhaoyan-Desktop-AI-competition-2026-Competition-code-MiraNote-AI-postdemo/"
        + "65508d89-6318-47c3-8753-699cde813603/scratchpad/ios-shots/a4")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: Helpers

    private func launch(schedules: Bool) {
        app.launchArguments = ["-UITEST", "-UITEST-TRIGGER", "-TRIGGER-FAKE-AI", "-TRIGGER-MANY-GROUPS"]
            + (schedules ? [] : ["-TRIGGER-NO-SCHEDULE"])
        app.launch()
    }

    private func scrollToHittable(_ element: XCUIElement, tries: Int = 10) {
        for _ in 0..<tries where !element.isHittable {
            app.swipeUp()
        }
    }

    /// Waits for the nights to be planned (the schedule probe), when the app plans them.
    private func waitForSevenNights() {
        let probe = app.staticTexts["debug.triggerSchedule"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline, probe.label.split(separator: ";").count < 7 {
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertEqual(probe.label.split(separator: ";").count, 7, "eight groups fill the seven nights")
    }

    @discardableResult
    private func openDetails() -> XCUIElement {
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        let link = app.buttons["trigger.allDetails"]
        scrollToHittable(link)
        link.tap()
        let screen = app.descendants(matching: .any)["debug.screen"].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 6))
        return screen
    }

    private func section(_ id: String) -> XCUIElement {
        app.buttons["debug.section.\(id)"].firstMatch
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? FileManager.default.createDirectory(at: Self.shotFolder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: Self.shotFolder.appendingPathComponent("\(name).png"))
    }

    private func rows(_ prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    private func progressLine(_ prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    // MARK: Tests

    func testDebugScreenHasEverySection() {
        launch(schedules: true)
        waitForSevenNights()
        openDetails()

        for (id, name) in [("preview", "1-preview"), ("tryOutside", "2-try-outside"), ("scheduled", "3-scheduled")] {
            let header = section(id)
            XCTAssertTrue(header.waitForExistence(timeout: 4), id)
            scrollToHittable(header)
            shot("a4-\(name)")
        }
        XCTAssertEqual(rows("debug.push.").count, 7, "seven nights, each with its push")

        // The log is folded away until opened.
        let log = section("log")
        scrollToHittable(log)
        log.tap()
        XCTAssertTrue(app.descendants(matching: .any)["debug.run"].firstMatch.waitForExistence(timeout: 3))
        shot("a4-4-log")

        let blocked = section("blocked")
        XCTAssertTrue(blocked.exists)
        scrollToHittable(blocked)
        XCTAssertTrue(app.staticTexts["Nothing is blocked"].exists)
        shot("a4-6-blocked")

        let actions = section("actions")
        scrollToHittable(actions)
        let copy = app.buttons["debug.copyLedger"]
        scrollToHittable(copy)
        copy.tap()
        XCTAssertTrue(app.staticTexts["debug.copied"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["debug.replan"].exists)
        XCTAssertTrue(app.buttons["debug.clear"].exists)
        shot("a4-7-actions")

        XCTAssertTrue(section("category").exists)
        XCTAssertTrue(section("grouping").exists)

        // Grouping results: a card per group, with its photos.
        let grouping = section("grouping")
        scrollToHittable(grouping)
        grouping.tap()
        XCTAssertTrue(rows("debug.group").firstMatch.waitForExistence(timeout: 6))
        XCTAssertGreaterThanOrEqual(rows("debug.group").count, 8)
        XCTAssertTrue(app.staticTexts["Can go out"].firstMatch.exists)
        shot("a4-5-grouping")
        app.navigationBars.buttons.firstMatch.tap()

        let category = section("category")
        scrollToHittable(category)
        category.tap()
        XCTAssertTrue(app.descendants(matching: .any)["debug.category.food"].firstMatch.waitForExistence(timeout: 6))
        shot("a4-8-category")
    }

    func testPreviewCyclesScheduledPushes() {
        launch(schedules: true)
        waitForSevenNights()
        openDetails()
        let button = app.buttons["debug.preview"]
        let notice = app.staticTexts["trigger.notice"]
        var seen: [String] = []
        for _ in 0..<2 {
            scrollToHittable(button)
            XCTAssertTrue(button.waitForExistence(timeout: 4))
            let deadline = Date().addingTimeInterval(10)
            while !button.isEnabled, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            button.tap()
            XCTAssertTrue(notice.waitForExistence(timeout: 10))
            let label = notice.label
            let deadline2 = Date().addingTimeInterval(10)
            while seen.last == label, Date() < deadline2 { Thread.sleep(forTimeInterval: 0.3) }
            seen.append(notice.label)
        }
        XCTAssertEqual(seen.count, 2)
        XCTAssertNotEqual(seen[0], seen[1], "the second press previews the next night: \(seen)")
        shot("a4-preview-cycles")
    }

    func testTryOutsideShowsProgress() {
        launch(schedules: false)
        openDetails()
        let button = app.buttons["debug.tryOutside"]
        scrollToHittable(button)
        button.tap()
        XCTAssertTrue(progressLine("Preparing").waitForExistence(timeout: 6))
        XCTAssertTrue(progressLine("Scheduled, the push comes in 10 s (rank 1").waitForExistence(timeout: 25))
        XCTAssertTrue(progressLine("Asking the AI...").exists)
        shot("a4-try-outside-progress")
    }

    func testClearEverythingAsksFirst() {
        launch(schedules: true)
        waitForSevenNights()
        openDetails()
        XCTAssertEqual(rows("debug.push.").count, 7)
        let clear = app.buttons["debug.clear"]
        scrollToHittable(clear)
        clear.tap()

        // Asked first; dismissing the popover (no Cancel button on iPad-style
        // popovers, a Cancel button on action sheets) changes nothing.
        let confirm = app.buttons["Yes, clear everything"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        shot("a4-clear-dialog")
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.92)).tap()
        }
        XCTAssertFalse(confirm.waitForExistence(timeout: 1))
        XCTAssertEqual(rows("debug.push.").count, 7, "cancelling keeps the schedule")

        scrollToHittable(clear)
        clear.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        let deadline = Date().addingTimeInterval(8)
        while rows("debug.push.").count > 0, Date() < deadline { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(rows("debug.push.").count, 0, "everything is cleared")
        XCTAssertEqual(rows("debug.empty.").count, 7, "the nights are empty again")
        shot("a4-cleared")
    }

    func testPhase1PushOneButtonIsGone() {
        launch(schedules: false)
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        let link = app.buttons["trigger.allDetails"]
        scrollToHittable(link)
        XCTAssertTrue(link.exists, "Home links to the full debug screen")
        XCTAssertTrue(app.buttons["trigger.preview"].exists)
        XCTAssertTrue(app.buttons["trigger.tryOutside"].exists)
        XCTAssertFalse(app.buttons["trigger.pushTop"].exists, "phase 1's push-one button is gone")
        XCTAssertFalse(app.buttons["trigger.pushNext"].exists)
        XCTAssertFalse(app.buttons["Push one in 10 s"].exists)
        XCTAssertFalse(app.buttons["Push the next group"].exists)
        shot("a4-home-card")
    }
}
