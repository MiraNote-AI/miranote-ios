import XCTest

/// The story's "..." menu changes what gets pushed (phase 2, task A2).
/// The schedule is read from `debug.triggerSchedule`, a hidden DEBUG text
/// ("slotDay=belongsTo;..."): the debug screen does not exist yet.
extension PhotoTriggerUITests {
    /// The zh-Hans name of the food bucket (group A's), as Unicode escapes:
    /// Swift source stays ASCII (org rule 3).
    private var foodBucketName: String { "\u{7F8E}\u{98DF}\u{996E}\u{54C1}" }

    func testOtherBucketMenuHasOnlyNotThisDay() {
        launch(["-TRIGGER-FAKE-AI", "-TRIGGER-OTHER-ONLY"])
        pushAndWait()
        openLatestPush()
        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 8))
        more.tap()
        XCTAssertTrue(app.buttons["Not this day"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Fewer like this"].exists, "nothing to lower for the other bucket")
        shot("a2-other-menu")
    }

    func testFewerLikeThisNamesTheBucket() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        openLatestPush()
        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 8))
        more.tap()
        app.buttons["Fewer like this"].tap()
        let note = app.staticTexts["trigger.menuNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 2))
        XCTAssertEqual(note.label, "Fewer like \"\(foodBucketName)\" from now on")
    }

    func testNotThisDayRemovesThatDaysScheduledPush() {
        let arguments = ["-UITEST", "-UITEST-TRIGGER", "-TRIGGER-FAKE-AI", "-TRIGGER-MANY-GROUPS"]
        app.launchArguments = arguments
        app.launch()
        let before = scheduledDays(count: 7)
        XCTAssertEqual(before.count, 7, "eight groups fill the seven nights")

        // A tap on the newest push; its first frame names its day ("11.01").
        app.terminate()
        app.launchArguments = arguments + ["-KEEP_SETTINGS", "-TRIGGER-OPEN-PUSH", "latest"]
        app.launch()
        let label = app.staticTexts["trigger.firstFrameLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        let pushed = before.first { $0.belongsTo.hasSuffix("-" + label.label.replacingOccurrences(of: ".", with: "-")) }
        XCTAssertNotNil(pushed, "the story's day is one of the scheduled days: \(label.label) in \(before)")
        app.buttons["More"].tap()
        app.buttons["Not this day"].tap()
        XCTAssertTrue(app.staticTexts["trigger.menuNote"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 6))

        // The day is gone from the schedule and the spare group fills the night.
        let after = scheduledDays(count: 7) { !$0.contains { $0.belongsTo == pushed?.belongsTo } }
        XCTAssertFalse(after.contains { $0.belongsTo == pushed?.belongsTo }, "that day is not pushed again")
        XCTAssertEqual(after.count, 7, "a new group fills the night")
        shot("a2-not-this-day")
    }

    // MARK: The schedule

    private struct Night: CustomStringConvertible {
        let slotDay: String
        let belongsTo: String
        var description: String { "\(slotDay)=\(belongsTo)" }
    }

    /// Waits for the schedule probe to list `count` nights (and `also` to
    /// hold), then returns them.
    private func scheduledDays(count: Int, also: ([Night]) -> Bool = { _ in true }) -> [Night] {
        let probe = app.staticTexts["debug.triggerSchedule"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 15))
        var nights: [Night] = []
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            nights = (probe.label.isEmpty ? [] : probe.label.split(separator: ";").map(String.init)).compactMap {
                let parts = $0.split(separator: "=").map(String.init)
                return parts.count == 2 ? Night(slotDay: parts[0], belongsTo: parts[1]) : nil
            }
            if nights.count >= count, also(nights) { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nights
    }
}
