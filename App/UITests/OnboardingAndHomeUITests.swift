import XCTest

/// Handoff screens 01 and 03: Home leads with Start, and the first blank
/// page introduces the five tools once.
final class OnboardingAndHomeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDownWithError() throws {
        app = nil
    }

    private func launch(_ arguments: [String]) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"] + arguments
        app.launch()
    }

    func testHomeLeadsWithStartThenSearch() {
        launch([])
        let start = app.buttons["Start a memory"]
        let search = app.textFields["quick.field"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertTrue(search.exists)
        XCTAssertLessThan(start.frame.maxY, search.frame.minY, "Start sits above the search pill")
        XCTAssertGreaterThanOrEqual(start.frame.height, 90, "the handoff's large Start button")
        XCTAssertEqual(app.buttons["collection.Daily Log"].label, "Daily Log",
                       "cards carry their title only, no note count (screen 01)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "home"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testToolsOnboardingLeadsToTheBackgroundTool() {
        launch(["-HINT", "editor-tools"])
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(intro.waitForExistence(timeout: 5), "a first blank page introduces the tools")
        XCTAssertTrue(app.staticTexts["Create your way"].exists)
        XCTAssertTrue(app.staticTexts["Tap an icon to switch tools"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "tools onboarding"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["onboarding.background"].tap()
        waitUntilGone(intro)
        XCTAssertTrue(app.staticTexts["background.title"].waitForExistence(timeout: 5),
                      "the handoff flow goes on to the Background tool")
    }

    func testNextAlsoGoesOnToBackground() {
        launch(["-HINT", "editor-tools"])
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        waitUntilGone(intro)
        XCTAssertTrue(app.staticTexts["background.title"].waitForExistence(timeout: 5))
    }

    func testBackJustCloses() {
        launch(["-HINT", "editor-tools"])
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        waitUntilGone(intro)
        XCTAssertFalse(app.staticTexts["background.title"].exists)
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5), "on the blank canvas")
    }

    // The introduction is a screen of its own: no tool bar acts while it is
    // up, and a tap where the tool bar will be does nothing.
    func testNoToolActsWhileTheIntroIsUp() {
        launch(["-HINT", "editor-tools"])
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mode.text"].exists, "no tool bar under the introduction")
        let toolBar = CGVector(dx: intro.frame.midX, dy: intro.frame.maxY + 40)
        app.coordinate(withNormalizedOffset: .zero).withOffset(toolBar).tap()
        sleep(1)
        XCTAssertTrue(intro.exists, "the introduction stays until it is answered")
        XCTAssertFalse(app.descendants(matching: .any)["canvas.textEditor"].exists)
    }

    // Tapping a tool's row (or its icon) graduates the introduction and
    // opens that tool -- the Text row drops a block to type into.
    func testTappingAToolRowOpensThatTool() {
        launch(["-HINT", "editor-tools"])
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        app.buttons["onboarding.tool.text"].tap()
        waitUntilGone(intro)
        XCTAssertTrue(app.descendants(matching: .any)["canvas.textEditor"].waitForExistence(timeout: 5),
                      "the Text tool opened")
    }

    /// The card by id, whatever element type its modal trait gives it.
    private var intro: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "onboarding.tools").firstMatch
    }

    private func waitUntilGone(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 3), .completed)
    }

    func testOtherUITestLaunchesNeverSeeIt() {
        launch([])
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        XCTAssertFalse(intro.exists)
    }
}
