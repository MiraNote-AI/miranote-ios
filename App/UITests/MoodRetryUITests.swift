import XCTest

/// #159: a saved page whose mood ask hit a service hiccup is asked again,
/// and its star in the jar takes the color late. `-MOOD_FAIL_FIRST <n>`
/// fails the first n asks as an unreachable backend does; then the mock
/// reads "happy" as joyful.
final class MoodRetryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Launches with `failures` mood asks failing, saves a page with
    /// `words`, opens the jar right away and returns the page's star.
    private func saveAndOpenTheJar(failures: Int, words: String) -> XCUIElement {
        app.launchArguments = ["-UITEST", "-MOOD_FAIL_FIRST", "\(failures)"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
        app.buttons["keyboard.done"].tap()
        app.buttons["Save"].tap()

        let entry = app.buttons["home.starJar"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()
        XCTAssertTrue(app.staticTexts["Star jar"].waitForExistence(timeout: 5))
        let star = app.buttons["jar.star.\(words)"]
        XCTAssertTrue(star.waitForExistence(timeout: 5), "the page is a star in this month's jar")
        return star
    }

    private func label(of element: XCUIElement, becomes expected: String, within timeout: TimeInterval) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [match], timeout: timeout), .completed,
                       "label is \(element.label), expected \(expected)")
    }

    /// One hiccup at Save; the jar is opened at once and left open. The
    /// star is grey, then takes its color by itself after the first
    /// backoff step (10 s).
    func testALateMoodColorsTheStarWhileTheJarIsOpen() {
        let star = saveAndOpenTheJar(failures: 1, words: "A happy picnic")
        XCTAssertEqual(star.label, "A happy picnic, mood not read yet", "grey while the ask waits out its pause")
        label(of: star, becomes: "A happy picnic, Joyful", within: 25)
    }

    /// Three hiccups spend every try (after 10 s and 60 s); the open jar
    /// stays grey. Coming back to the app asks again, and the star takes
    /// its color.
    func testComingBackToTheAppAsksAgainOnceTriesAreSpent() {
        let star = saveAndOpenTheJar(failures: 3, words: "A happy picnic")
        // Three asks and 70 s of backoff, with a margin.
        Thread.sleep(forTimeInterval: 85)
        XCTAssertEqual(star.label, "A happy picnic, mood not read yet", "every try spent")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        label(of: star, becomes: "A happy picnic, Joyful", within: 8)
    }
}
