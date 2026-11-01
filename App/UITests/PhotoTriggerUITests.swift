import XCTest

/// The photo trigger's demo, end to end: Home's demo entry opens the story,
/// taps step through it, the last photo gathers into the ending card, and
/// the button closes back to Home. Needs the bundled demo memory (built
/// from the untracked demo-input/), so a checkout without it skips.
///
/// `TRIGGER_SHOTS=<dir>` (as TEST_RUNNER_TRIGGER_SHOTS for xcodebuild)
/// saves screenshots of each step there, the gather as a burst.
final class PhotoTriggerUITests: XCTestCase {
    private var shotDirectory: URL?
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        // V1: the bundled demo memory (personal photos) is gone; these come
        // back on the synthetic -UITEST-TRIGGER library.
        throw XCTSkip("waiting for the synthetic trigger library (V1 task 9)")
        continueAfterFailure = false
        shotDirectory = ProcessInfo.processInfo.environment["TRIGGER_SHOTS"].map { URL(fileURLWithPath: $0) }
        app = XCUIApplication()
        app.launchArguments = ["-DEMO-SAMPLES"]
        app.launch()
    }

    func testStoryGathersIntoTheEnding() throws {
        let open = app.buttons["trigger.demo.open"]
        for _ in 0..<4 where !open.isHittable {
            app.swipeUp()
        }
        guard open.exists else { throw XCTSkip("no bundled demo memory") }
        shot("00-home")
        open.tap()

        XCTAssertTrue(photo(1).waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)
        shot("01-first")

        // Autoplay: photo 2 after the first photo's 2 s.
        XCTAssertTrue(photo(2).waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.5)
        shot("02-second")

        let screen = app.windows.firstMatch
        let right = screen.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let left = screen.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        for _ in 0..<5 {
            right.tap()
        }
        XCTAssertTrue(photo(7).waitForExistence(timeout: 2))
        left.tap()
        XCTAssertTrue(photo(6).waitForExistence(timeout: 2))
        right.tap()
        right.tap()
        XCTAssertTrue(photo(8).waitForExistence(timeout: 2))
        Thread.sleep(forTimeInterval: 0.4)
        shot("03-peak")

        // The peak's 3 s, then the gather: a burst across it.
        Thread.sleep(forTimeInterval: 2.3)
        for frame in 0..<14 {
            shot(String(format: "04-gather-%02d", frame))
        }

        let keep = app.buttons["trigger.keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 4))
        Thread.sleep(forTimeInterval: 1)
        shot("05-ending")
        keep.tap()
        let ok = app.alerts.buttons.firstMatch
        XCTAssertTrue(ok.waitForExistence(timeout: 2))
        shot("06-notice")
        ok.tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 3))
    }

    /// "Push now" asks for permission the first time, then the push lands
    /// three seconds later as a banner -- with the app still in front.
    func testPushArrivesAsABannerInTheForeground() throws {
        let push = app.buttons["trigger.demo.push"]
        for _ in 0..<4 where !push.isHittable {
            app.swipeUp()
        }
        guard push.exists else { throw XCTSkip("no bundled demo memory") }
        push.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // The permission prompt, first time only. Its buttons follow the
        // simulator's language: "Allow" is the second either way.
        let prompt = springboard.alerts.firstMatch
        if prompt.waitForExistence(timeout: 3) {
            shot("10-permission")
            prompt.buttons.element(boundBy: 1).tap()
        }

        let banner = springboard.descendants(matching: .any)["NotificationShortLookView"]
        XCTAssertTrue(banner.waitForExistence(timeout: 8), "no banner within 8 s")
        XCTAssertTrue(banner.label.uppercased().hasPrefix("MIRANOTE"), banner.label)
        shot("11-banner")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// With the app in the background the push looks as it will on a
    /// phone; pulled down in Notification Center it expands to its photo.
    func testPushInTheBackgroundShowsItsCover() throws {
        let push = app.buttons["trigger.demo.push"]
        for _ in 0..<4 where !push.isHittable {
            app.swipeUp()
        }
        guard push.exists else { throw XCTSkip("no bundled demo memory") }
        push.tap()
        XCUIDevice.shared.press(.home)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.descendants(matching: .any)["NotificationShortLookView"]
        XCTAssertTrue(banner.waitForExistence(timeout: 8), "no banner within 8 s")
        shot("20-background-banner")
        banner.press(forDuration: 1.5)
        Thread.sleep(forTimeInterval: 1.5)
        shot("21-background-expanded")
    }

    /// A held finger stops the clock; a swipe steps either way; the menu
    /// offers its two items and only closes; the close button goes home.
    func testHoldSwipeMenuAndClose() throws {
        let open = app.buttons["trigger.demo.open"]
        for _ in 0..<4 where !open.isHittable {
            app.swipeUp()
        }
        guard open.exists else { throw XCTSkip("no bundled demo memory") }
        open.tap()
        XCTAssertTrue(photo(1).waitForExistence(timeout: 5))

        // Held past the photo's 2 s: still the first photo.
        let screen = app.windows.firstMatch
        screen.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).press(forDuration: 3)
        XCTAssertTrue(photo(1).exists, "the story moved on under a held finger")

        screen.swipeLeft()
        XCTAssertTrue(photo(2).waitForExistence(timeout: 1))
        screen.swipeRight()
        XCTAssertTrue(photo(1).waitForExistence(timeout: 1))

        app.buttons["\u{66F4}\u{591A}"].tap()   // "More"
        XCTAssertTrue(app.buttons["\u{5C11}\u{63A8}\u{8FD9}\u{7C7B}"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["\u{4E0D}\u{60F3}\u{770B}\u{8FD9}\u{4E00}\u{5929}"].exists)
        shot("30-menu")
        app.buttons["\u{5C11}\u{63A8}\u{8FD9}\u{7C7B}"].tap()
        // The menu only closes: the story carries on where it was (the
        // first photo may have run out just before the menu paused it).
        XCTAssertTrue(photo(1).waitForExistence(timeout: 1) || photo(2).exists)

        app.buttons["\u{5173}\u{95ED}"].tap()   // "Close"
        XCTAssertTrue(app.buttons["trigger.demo.open"].waitForExistence(timeout: 3))
    }

    /// The story's position, as VoiceOver reads it.
    private func photo(_ number: Int) -> XCUIElement {
        app.descendants(matching: .any)["Photo \(number) of 8"].firstMatch
    }

    private func shot(_ name: String) {
        guard let shotDirectory else { return }
        try? FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: shotDirectory.appendingPathComponent("\(name).png"))
    }
}
