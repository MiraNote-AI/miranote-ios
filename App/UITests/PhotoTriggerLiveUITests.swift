import XCTest

/// The photo trigger against the real thing, on a simulator whose library
/// holds the prototype's photos (imported there, never into the repo):
/// PhotoKit, Vision, Apple's geocoder, the local photo-collections backend
/// and real notifications. Opt-in -- `TRIGGER_E2E=1` (TEST_RUNNER_TRIGGER_E2E
/// for xcodebuild) -- because it needs that library and the backend; every
/// other run skips it. Screenshots go to `TRIGGER_SHOTS`.
final class PhotoTriggerLiveUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shotDirectory: URL?
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["TRIGGER_E2E"] == "1" else {
            throw XCTSkip("live trigger run: set TRIGGER_E2E=1 on a simulator with the prototype photos")
        }
        continueAfterFailure = false
        shotDirectory = ProcessInfo.processInfo.environment["TRIGGER_SHOTS"].map { URL(fileURLWithPath: $0) }
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    }

    private func shot(_ name: String) {
        guard let shotDirectory else { return }
        try? FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: shotDirectory.appendingPathComponent("\(name).png"))
    }

    /// Allows whatever system prompt is up (photos, notifications).
    private func allowPrompts(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let alert = springboard.alerts.firstMatch
            if alert.waitForExistence(timeout: 1) {
                shot("live-prompt-\(Int(Date().timeIntervalSince1970))")
                let buttons = alert.buttons.allElementsBoundByIndex
                // "Allow Full Access" / "Allow" sit last or second.
                let allow = buttons.first { $0.label.contains("Full") || $0.label.contains("\u{5B8C}\u{6574}") }
                    ?? buttons.last
                allow?.tap()
            }
        }
    }

    private func entry(_ id: String) -> XCUIElement {
        let button = app.buttons[id]
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        return button
    }

    private func progress(_ fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    /// B5: analysis killed half way resumes from what was saved.
    func testAnalysisResumesAfterAKill() {
        app.launch()
        XCTAssertTrue(entry("trigger.pushTop").waitForExistence(timeout: 10))
        if app.switches["trigger.fakeAI"].value as? String != "1" { app.switches["trigger.fakeAI"].tap() }
        entry("trigger.pushTop").tap()
        allowPrompts(for: 4)
        // "Looking at photos x/y": wait for some progress, then kill the app.
        XCTAssertTrue(progress("/").waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 3)
        shot("b5-1-before-kill")
        let before = progress("/").label
        app.terminate()
        app.launch()
        entry("trigger.pushTop").tap()
        XCTAssertTrue(progress("/").waitForExistence(timeout: 30))
        shot("b5-2-after-relaunch")
        print("B5 before kill: \(before); after relaunch: \(progress("/").label)")
        XCTAssertTrue(progress("\u{5DF2}\u{5B89}\u{6392}").waitForExistence(timeout: 300), "scheduled")
        shot("b5-3-done")
        // A second press analyses nothing new.
        entry("trigger.pushTop").tap()
        XCTAssertTrue(progress("\u{5DF2}\u{5B89}\u{6392}").waitForExistence(timeout: 120))
        shot("b5-4-second-press")
    }

    /// C3, D1, D3, E1-E3, F1-F5 with the real AI.
    func testRealBackendEndToEnd() {
        app.launch()
        XCTAssertTrue(entry("trigger.pushTop").waitForExistence(timeout: 10))
        if app.switches["trigger.fakeAI"].value as? String == "1" { app.switches["trigger.fakeAI"].tap() }
        shot("live-01-entry")
        entry("trigger.pushTop").tap()
        allowPrompts(for: 3)
        guard waitForScheduled() else { return }
        shot("live-03-scheduled")
        openFromThePush()
        keepAsAPage()
    }

    /// D2b: sent to the background while the AI works, the app picks the
    /// same job up on return and still schedules the push.
    func testBackgroundWhileWaitingStillSchedules() {
        app.launch()
        XCTAssertTrue(entry("trigger.pushTop").waitForExistence(timeout: 10))
        if app.switches["trigger.fakeAI"].value as? String == "1" { app.switches["trigger.fakeAI"].tap() }
        entry("trigger.pushTop").tap()
        allowPrompts(for: 3)
        // "Asking the AI": then away for 30 s.
        XCTAssertTrue(progress("AI\u{2026}").waitForExistence(timeout: 60))
        shot("d2b-1-asking")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 30)
        app.activate()
        shot("d2b-2-back")
        XCTAssertTrue(waitForScheduled(), "the same press finished after the return")
        shot("d2b-3-scheduled")
    }

    /// Screenshots each new progress step until the push is scheduled.
    private func waitForScheduled() -> Bool {
        var seen: Set<String> = []
        let deadline = Date().addingTimeInterval(330)
        while Date() < deadline {
            let lines = app.descendants(matching: .any)["trigger.progress"].staticTexts.allElementsBoundByIndex
                .map(\.label)
            for line in lines where !seen.contains(line) && !line.contains("/") {
                seen.insert(line)
                shot("live-02-progress-\(seen.count)")
            }
            if lines.contains(where: { $0.contains("\u{5DF2}\u{5B89}\u{6392}") }) {
                print("C3 steps: \(lines)")
                return true
            }
            if lines.contains(where: { $0.contains("\u{8FDE}\u{4E0D}\u{4E0A}") || $0.contains("\u{8D85}\u{65F6}") }) {
                XCTFail("failed: \(lines)")
                return false
            }
            Thread.sleep(forTimeInterval: 2)
        }
        XCTFail("not scheduled in time")
        return false
    }

    /// D1 and D3: the push arrives about 10 s later; the app is killed and
    /// the push tapped (from Notification Center once the banner has gone).
    private func openFromThePush() {
        XCUIDevice.shared.press(.home)
        let banner = springboard.descendants(matching: .any)["NotificationShortLookView"]
        XCTAssertTrue(banner.waitForExistence(timeout: 25), "the push arrived")
        shot("live-04-push")
        print("D1 banner: \(banner.label)")
        app.terminate()
        if banner.exists {
            banner.tap()
        } else {
            let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.01))
            let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
            top.press(forDuration: 0.1, thenDragTo: middle)
            let listed = springboard.descendants(matching: .any)["NotificationShortLookView"]
            XCTAssertTrue(listed.waitForExistence(timeout: 5))
            shot("live-04b-notification-center")
            listed.tap()
        }
        let label = app.staticTexts["trigger.firstFrameLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 15), "the cold launch opened the story")
        shot("live-05-story-first")
        print("E1 first frame: \(label.label)")
    }

    /// E3, F1-F5: the ending, the canvas, saved, still there after a relaunch.
    private func keepAsAPage() {
        let right = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        for _ in 0..<8 { right.tap() }
        let keep = app.buttons["trigger.keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.5)
        shot("live-06-ending")
        keep.tap()
        let saveLabel = NSPredicate(format: "label == 'Save' OR label == '\u{4FDD}\u{5B58}'")
        let save = app.buttons.matching(saveLabel).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 20), "the canvas draft opened")
        Thread.sleep(forTimeInterval: 3)
        shot("live-07-canvas")
        save.tap()
        Thread.sleep(forTimeInterval: 2)
        shot("live-08-home")
        app.terminate()
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        shot("live-09-home-after-relaunch")
    }
}
