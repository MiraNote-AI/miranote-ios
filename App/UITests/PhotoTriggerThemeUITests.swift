import XCTest

/// A repeat theme's push on the synthetic library (acceptance E2-E5, spec
/// 6.9): the library's themes are found and the first is test-pushed on
/// launch (`-TRIGGER-TRY-THEME`, as the debug page's button would), then
/// the push is opened as a tap would (`-TRIGGER-OPEN-PUSH latest`). The
/// scripted backend writes the memory the way the backend does;
/// `-TRIGGER-FAKE-AI` has the phone write it from the catalog's words.
/// Chinese is written as escapes (org rule 3).
///
/// `TRIGGER_SHOTS=<dir>` (TEST_RUNNER_TRIGGER_SHOTS for xcodebuild) saves
/// screenshots of each step there.
final class PhotoTriggerThemeUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shotDirectory: URL?

    /// The first theme of the synthetic library: "home dinner", noun "dinner".
    private let themeName = "\u{5BB6}\u{91CC}\u{7684}\u{665A}\u{996D}"
    private let noun = "\u{665A}\u{996D}"
    private let separator = " \u{00B7} "
    private let month = "\u{6708}"
    /// "Keep these ".
    private let keepThese = "\u{7559}\u{4F4F}\u{8FD9}\u{4E9B}"

    override func setUpWithError() throws {
        continueAfterFailure = false
        shotDirectory = ProcessInfo.processInfo.environment["TRIGGER_SHOTS"].map { URL(fileURLWithPath: $0) }
        app = XCUIApplication()
    }

    // MARK: E2 -- the story

    func testRepeatStoryFirstCardShowsThemeAndMonths() {
        pushTheme()
        // 4x the time on screen: XCUITest keeps up with each photo.
        let count = openPush(["-TRIGGER-SLOW-STORY"])
        XCTAssertTrue((5...9).contains(count), "\(count) photos")
        let label = app.staticTexts["trigger.firstFrameLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 4))
        XCTAssertTrue(label.label.hasPrefix(themeName + separator), label.label)
        XCTAssertTrue(label.label.hasSuffix(month), "the months, not a day: \(label.label)")
        // The scripted backend's peak is P1.
        XCTAssertEqual(app.descendants(matching: .any)["trigger.photo.P1"].label, "Photo 1 of \(count)")
        shot("repeat-story-first-card")

        // The other photos carry no words, no date on any of them (the
        // label fades out but stays in the tree: the shot shows it).
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        XCTAssertTrue(photo(2, of: count).waitForExistence(timeout: 4))
        shot("repeat-story-photo-2")
    }

    // MARK: E3 -- the menu

    func testRepeatMenuHasOnlyNotThisTheme() {
        pushTheme()
        _ = openPush()
        app.buttons["More"].tap()
        XCTAssertTrue(app.buttons["Not this theme"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Not this day"].exists, "a repeat push has no day to block")
        XCTAssertFalse(app.buttons["Fewer like this"].exists, "nor a bucket to lower")
        shot("repeat-menu")
    }

    /// "Not this theme": the note, the story closes, and the theme is
    /// blocked -- a test push of it on the next launch is refused.
    func testNotThisThemeBlocksTheme() {
        pushTheme()
        _ = openPush()
        app.buttons["More"].tap()
        app.buttons["Not this theme"].tap()
        let note = app.staticTexts["trigger.menuNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 2))
        XCTAssertEqual(note.label, "This theme won't be pushed again")
        shot("repeat-not-this-theme")
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 6), "the story closed")

        app.terminate()
        launch(["-TRIGGER-TRY-THEME"], keep: true)
        XCTAssertTrue(progressLine("Not pushed: The theme is blocked").waitForExistence(timeout: 40))
    }

    // MARK: E4 -- the landing page

    /// The fake AI's memory: the button and the question in the catalog's
    /// Chinese, with the theme's noun.
    func testRepeatLandingButtonKeepTheseNoun() {
        pushTheme(["-TRIGGER-FAKE-AI"])
        let count = openPush()
        let keep = skipToEnding(photos: count)
        XCTAssertEqual(keep.label, keepThese + noun)
        let fact = app.staticTexts["trigger.factLine"]
        XCTAssertTrue(fact.label.hasPrefix(themeName + separator) && fact.label.hasSuffix(month), fact.label)
        // "Three keywords for these dinner?"
        let question = "\u{8FD9}\u{4E9B}" + noun + "\u{7684}\u{4E09}\u{4E2A}\u{5173}\u{952E}\u{8BCD}\u{FF1F}"
        XCTAssertEqual(app.staticTexts["trigger.question"].label, question)
        shot("repeat-landing")
    }

    // MARK: E5 -- the canvas

    /// Every photo of the push on the page, titled with the fact line and
    /// dated today, the day it was made -- not the photos' day.
    func testRepeatCanvasHasFiveToNinePhotosAndTodayDate() {
        pushTheme()
        let count = openPush()
        let keep = skipToEnding(photos: count)
        XCTAssertEqual(keep.label, keepThese + noun, "the scripted backend's button too")
        let title = app.staticTexts["trigger.factLine"].label
        keep.tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the canvas opened")
        let photos = app.images.matching(identifier: "element.image")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(photos.count, count)
        XCTAssertTrue((5...9).contains(photos.count), "\(photos.count) photos")
        shot("repeat-canvas")

        save.tap()
        let log = app.buttons["collection.Daily Log"]
        XCTAssertTrue(log.waitForExistence(timeout: 6))
        log.tap()
        let page = app.buttons["note.\(title)"]
        XCTAssertTrue(page.waitForExistence(timeout: 5), "filed under the fact line")
        // Its own caption (a seeded page is dated today too).
        let today = Self.caption(Date())
        XCTAssertTrue(page.staticTexts[today].exists || page.label.contains(today),
                      "dated \(today), the day it was made: \(page.label)")
        shot("repeat-canvas-filed")
    }

    // MARK: Helpers

    private func launch(_ extra: [String], keep: Bool = false) {
        app.launchArguments = ["-UITEST", "-UITEST-TRIGGER", "-TRIGGER-NO-SCHEDULE"]
            + (keep ? ["-KEEP_SETTINGS"] : []) + extra
        app.launch()
    }

    /// Finds the themes, test-pushes the first and waits for "Scheduled".
    private func pushTheme(_ extra: [String] = []) {
        launch(["-TRIGGER-TRY-THEME"] + extra)
        XCTAssertTrue(progressLine("Scheduled").waitForExistence(timeout: 40), "the theme was pushed")
    }

    /// Relaunches as a tap on the push would; returns the story's length.
    private func openPush(_ extra: [String] = []) -> Int {
        app.terminate()
        launch(["-TRIGGER-OPEN-PUSH", "latest"] + extra, keep: true)
        let first = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Photo 1 of ")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "the push opened its story")
        return Int(first.label.components(separatedBy: " ").last ?? "") ?? 0
    }

    /// A line of Home's debug entry, scrolled into view.
    private func progressLine(_ prefix: String) -> XCUIElement {
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        let button = app.buttons["trigger.tryOutside"]
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        return app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func photo(_ number: Int, of count: Int) -> XCUIElement {
        app.descendants(matching: .any)["Photo \(number) of \(count)"].firstMatch
    }

    /// Steps through the story to the ending's button.
    private func skipToEnding(photos count: Int) -> XCUIElement {
        let right = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        for _ in 0..<count { right.tap() }
        let keep = app.buttons["trigger.keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 6))
        Thread.sleep(forTimeInterval: 1.2)
        return keep
    }

    /// A page's date as its cover's caption says it (`CaptionDate`, English).
    private static func caption(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en")
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        return formatter.string(from: date)
    }

    private func shot(_ name: String) {
        guard let shotDirectory else { return }
        try? FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: shotDirectory.appendingPathComponent("\(name).png"))
    }
}
