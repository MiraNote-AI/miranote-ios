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

    /// #160: Save on a new page sends its star into the jar circle once;
    /// leaving a blank page sends none.
    func testASavedNewPageFliesIntoTheJarCircle() {
        let jar = app.buttons["home.starJar"]
        XCTAssertTrue(jar.waitForExistence(timeout: 8))
        XCTAssertEqual(jar.value as? String, "0")

        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(jar.waitForExistence(timeout: 5))
        sleep(3)
        XCTAssertEqual(jar.value as? String, "0", "a blank page keeps nothing, so no star flies")

        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("A happy picnic")
        app.buttons["keyboard.done"].tap()
        app.buttons["Save"].tap()
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: jar)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 6), .completed, "the star lands once")
        XCTAssertEqual(jar.label, "Star jar", "the landing leaves the jar's name alone")
        sleep(2)
        XCTAssertEqual(jar.value as? String, "1", "and only once")
    }

    /// #160 with draft pages (#137): Home keeps a written page as a draft,
    /// which is not saved, so no star flies.
    func testADraftKeptByHomeSendsNoStar() {
        let jar = app.buttons["home.starJar"]
        XCTAssertTrue(jar.waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("A happy picnic")
        app.buttons["keyboard.done"].tap()
        app.buttons["Home"].tap()
        let toast = app.descendants(matching: .any).matching(identifier: "draft.toast").firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "the page was kept as a draft")
        sleep(3)
        XCTAssertEqual(jar.value as? String, "0", "a draft sends no star")
    }

    private var shakes: Int {
        // Home's probe stays under the pushed jar: read the jar's own.
        let probes = app.descendants(matching: .any).matching(identifier: "debug.state").allElementsBoundByIndex
        for probe in probes {
            guard let data = probe.label.data(using: .utf8),
                  let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  state["scene"] as? String == "jar" else { continue }
            return state["shakes"] as? Int ?? -1
        }
        return -1
    }

    /// A tap on the jar, away from any star, shakes it; a tap on a star
    /// still opens the page and does not shake.
    func testATapOnTheJarShakesIt() {
        openJar()
        XCTAssertEqual(shakes, 0)
        app.buttons["jar.period.week"].tap()
        app.buttons["jar.previous"].tap()
        app.buttons["jar.previous"].tap()
        let empty = app.staticTexts["jar.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 3))
        empty.tap()
        let shook = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.shakes == 1 }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shook], timeout: 3), .completed, "the jar shook once")
        empty.tap()
        let again = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.shakes == 2 }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [again], timeout: 3), .completed, "and again")
        XCTAssertFalse(app.buttons["reading.back"].exists, "no page opened")
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
