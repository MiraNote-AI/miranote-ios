import XCTest

/// The star jar: Home's jar circle opens it, a saved page lands in it as a
/// star colored by its mood (the mock reads "happy" as joyful), a star
/// opens its page, and Week / Month and the arrows move the period.
final class StarJarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func openJar() {
        let entry = app.buttons["home.starJar"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        XCTAssertEqual(entry.label, "Star jar")
        entry.tap()
        XCTAssertTrue(app.staticTexts["Star jar"].waitForExistence(timeout: 5))
    }

    private func label(of element: XCUIElement, becomes expected: String) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [match], timeout: 8), .completed,
                       "label is \(element.label), expected \(expected)")
    }

    func testASavedPageBecomesAStarThatOpensIt() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("A happy picnic")
        app.buttons["keyboard.done"].tap()
        app.buttons["Save"].tap()

        openJar()
        let star = app.buttons["jar.star.A happy picnic"]
        XCTAssertTrue(star.waitForExistence(timeout: 5), "the page is a star in this month's jar")
        label(of: star, becomes: "A happy picnic, Joyful")

        star.tap()
        XCTAssertTrue(app.buttons["reading.back"].waitForExistence(timeout: 5), "the star opens the page")
        app.buttons["reading.back"].tap()
        XCTAssertTrue(star.waitForExistence(timeout: 5), "back in the jar")
    }

    func testWeekMonthAndStepping() {
        openJar()
        let period = app.staticTexts["jar.period"]
        let thisMonth = period.label
        XCTAssertTrue(app.staticTexts["jar.summary"].waitForExistence(timeout: 5),
                      "the seed's pages are in this month")
        XCTAssertFalse(app.buttons["jar.next"].isEnabled, "nothing after the current month")

        app.buttons["jar.previous"].tap()
        XCTAssertNotEqual(period.label, thisMonth)
        XCTAssertTrue(app.buttons["jar.next"].isEnabled)
        app.buttons["jar.next"].tap()
        XCTAssertEqual(period.label, thisMonth)

        app.buttons["jar.period.week"].tap()
        XCTAssertTrue(app.buttons["jar.period.week"].isSelected)
        XCTAssertTrue(period.label.contains("\u{2013}"), "a week reads as a range: \(period.label)")
        XCTAssertTrue(app.staticTexts["jar.summary"].label.hasSuffix("this week"))
        app.buttons["jar.previous"].tap()
        app.buttons["jar.previous"].tap()
        XCTAssertTrue(app.staticTexts["jar.empty"].waitForExistence(timeout: 3), "an empty week says so")

        app.buttons["jar.period.month"].tap()
        XCTAssertTrue(app.buttons["jar.period.month"].isSelected)
    }
}
