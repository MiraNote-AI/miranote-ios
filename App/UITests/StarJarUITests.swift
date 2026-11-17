import XCTest

/// The star jar: Home's jar circle opens it, a saved page lands in it as a
/// star, a tap anywhere shakes the jar and a hold on a star opens its page
/// (#206), and Week / Month and the arrows move the period.
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
        label(of: star, becomes: "A happy picnic")

        star.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["reading.back"].waitForExistence(timeout: 5), "a hold opens the page")
        XCTAssertTrue(app.staticTexts["A happy picnic"].exists, "the held star's own page")
        app.buttons["reading.back"].tap()
        XCTAssertTrue(star.waitForExistence(timeout: 5), "back in the jar")
        XCTAssertTrue(star.isHittable, "the jar is back, its star with it")
        XCTAssertEqual(shakes, 0, "a hold does not shake the jar")
    }

    /// #206: under Reduce Motion the page cross-fades in and opens.
    func testUnderReduceMotionAHoldStillOpensThePage() {
        relaunch(["-REDUCE_MOTION"])
        _ = openSettledJar()
        let star = app.buttons["jar.star.Slow morning, good coffee"]
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        star.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["reading.back"].waitForExistence(timeout: 5), "the page opens")
        XCTAssertTrue(app.staticTexts["Slow morning, good coffee"].exists)
    }

    /// #206: a tap on a star shakes the jar and opens nothing -- before,
    /// any tap within 17 pt of a star opened it, so in a crowd the toss
    /// could not be reached. Only a hold opens.
    func testATapOnAStarShakesAndOnlyAHoldOpensIt() {
        relaunch(["-JAR_STARS", "30"])
        _ = openSettledJar()
        let star = app.buttons["jar.star.Star 1"]
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        star.tap()
        let shook = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.shakes == 1 }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shook], timeout: 3), .completed, "a tap on a star shakes")
        XCTAssertFalse(app.buttons["reading.back"].waitForExistence(timeout: 1), "and opens nothing")
        waitUntilSettled(tosses: 1, "the toss landed")

        // Let go during the tension (past the 120 ms tap window, before
        // 350 ms): the star springs back, nothing shakes, nothing opens.
        star.press(forDuration: 0.22)
        XCTAssertFalse(app.buttons["reading.back"].waitForExistence(timeout: 1), "a short press opens nothing")
        XCTAssertEqual(shakes, 1, "and shakes nothing")
        // Sliding away during the hold cancels it too.
        let from = star.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.2, thenDragTo: from.withOffset(CGVector(dx: 40, dy: 0)))
        XCTAssertFalse(app.buttons["reading.back"].waitForExistence(timeout: 1), "a slide opens nothing")
        XCTAssertEqual(shakes, 1)
        star.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["reading.back"].waitForExistence(timeout: 5), "a hold opens the page")
    }

    private var shakes: Int { jarState["shakes"] as? Int ?? -1 }

    private var anyStar: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jar.star.'")).firstMatch
    }

    private var jarState: [String: Any] {
        // Home's probe stays under the pushed jar: read the jar's own.
        let probes = app.descendants(matching: .any).matching(identifier: "debug.state").allElementsBoundByIndex
        for probe in probes {
            guard let data = probe.label.data(using: .utf8),
                  let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  state["scene"] as? String == "jar" else { continue }
            return state
        }
        return [:]
    }

    private func relaunch(_ arguments: [String]) {
        app.terminate()
        app.launchArguments = ["-UITEST"] + arguments
        app.launch()
    }

    /// Opens the jar and waits out the stars dropping in.
    private func openSettledJar() -> XCUIElement {
        openJar()
        let glass = app.otherElements["jar.glass"]
        XCTAssertTrue(glass.waitForExistence(timeout: 5))
        sleep(2)
        return glass
    }

    /// A tap in the jar's neck, above any star.
    private func tapNeck(of glass: XCUIElement) {
        glass.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
    }

    private func waitUntilSettled(tosses: Int, _ message: String) {
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.jarState["tosses"] as? Int == tosses && self.jarState["settled"] as? Bool == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 6), .completed, "\(message): \(jarState)")
    }

    /// #179: a tap on the jar tosses the stars, which land again; a star
    /// still opens its page after.
    func testAStarStillOpensAfterAToss() {
        let glass = openSettledJar()
        tapNeck(of: glass)
        waitUntilSettled(tosses: 1, "one toss, landed")
        XCTAssertEqual(shakes, 1)
        let star = app.buttons["jar.star.Slow morning, good coffee"]
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        star.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["reading.back"].waitForExistence(timeout: 5), "the star opens the page")
    }

    /// #179: fast taps keep a crowd in the air, and every star lands inside
    /// the glass.
    func testTossedStarsStayInTheJar() {
        relaunch(["-JAR_STARS", "60"])
        let glass = openSettledJar()
        for _ in 0..<3 { tapNeck(of: glass) }
        waitUntilSettled(tosses: 3, "three taps, one toss in the air, landed")
        let frame = glass.frame
        let stars = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jar.star.'"))
            .allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(stars.count, 60)
        for star in stars {
            let center = CGPoint(x: star.frame.midX, y: star.frame.midY)
            XCTAssertTrue(frame.insetBy(dx: 2, dy: 2).contains(center),
                          "\(star.identifier) at \(center) is outside the jar \(frame)")
            XCTAssertGreaterThan(center.y, frame.minY + frame.height * 0.06, "\(star.identifier) is under the lid")
        }
    }

    /// #179: under Reduce Motion a tap only sways the jar: no stars fly.
    func testReduceMotionSkipsTheToss() {
        relaunch(["-REDUCE_MOTION"])
        let glass = openSettledJar()
        tapNeck(of: glass)
        let shook = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.shakes == 1 }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shook], timeout: 3), .completed, "the jar sways")
        sleep(1)
        XCTAssertEqual(jarState["tosses"] as? Int, 0, "no star is thrown")
        XCTAssertEqual(jarState["settled"] as? Bool, true)
    }

    /// A tap on the jar, away from any star, shakes it.
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
        XCTAssertEqual(jar.value as? String, "0", "the page folds first: the star is not in yet")
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: jar)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 6), .completed, "the star lands once")
        XCTAssertEqual(jar.label, "Star jar", "the landing leaves the jar's name alone")
        sleep(2)
        XCTAssertEqual(jar.value as? String, "1", "and only once")
    }

    /// #206: Home scrolled down has its jar circle off the screen, so it
    /// is back at its top before the star flies in.
    func testAScrolledHomeIsBackAtTheTopForTheLanding() {
        let jar = app.buttons["home.starJar"]
        XCTAssertTrue(jar.waitForExistence(timeout: 8))
        let start = app.buttons["Start a memory"]
        let from = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -260)))
        sleep(1)
        XCTAssertFalse(jar.isHittable, "Home is scrolled: the jar circle is off the screen")

        XCTAssertTrue(start.isHittable)
        start.tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("A happy picnic")
        app.buttons["keyboard.done"].tap()
        app.buttons["Save"].tap()
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: jar)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 6), .completed, "the star lands")
        XCTAssertTrue(jar.isHittable, "Home is at its top: the star flew to a jar on the screen")
        XCTAssertGreaterThan(jar.frame.minY, 0)
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

    func testWeekMonthAndStepping() {
        openJar()
        let period = app.staticTexts["jar.period"]
        let thisMonth = period.label
        XCTAssertTrue(anyStar.waitForExistence(timeout: 5), "the seed's pages are in this month")
        XCTAssertFalse(app.staticTexts["jar.summary"].exists, "no count (#206): only the stars")
        XCTAssertFalse(app.buttons["jar.next"].isEnabled, "nothing after the current month")

        app.buttons["jar.previous"].tap()
        XCTAssertNotEqual(period.label, thisMonth)
        XCTAssertTrue(app.buttons["jar.next"].isEnabled)
        app.buttons["jar.next"].tap()
        XCTAssertEqual(period.label, thisMonth)

        app.buttons["jar.period.week"].tap()
        XCTAssertTrue(app.buttons["jar.period.week"].isSelected)
        XCTAssertTrue(period.label.contains("\u{2013}"), "a week reads as a range: \(period.label)")
        XCTAssertFalse(app.staticTexts["jar.empty"].exists, "this week holds the seed's pages")
        app.buttons["jar.previous"].tap()
        app.buttons["jar.previous"].tap()
        XCTAssertTrue(app.staticTexts["jar.empty"].waitForExistence(timeout: 3), "an empty week says so")

        app.buttons["jar.period.month"].tap()
        XCTAssertTrue(app.buttons["jar.period.month"].isSelected)
    }
}
