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
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "tools onboarding"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["onboarding.background"].tap()
        waitUntilGone(intro)
        XCTAssertTrue(app.buttons["background.default"].waitForExistence(timeout: 5),
                      "the handoff flow goes on to the Background tool")
    }

    func testSkipJustCloses() {
        launch(["-HINT", "editor-tools"])
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap()
        waitUntilGone(intro)
        XCTAssertFalse(app.buttons["background.default"].exists)
        XCTAssertTrue(app.buttons["mode.text"].exists)
    }

    // The tools behind the card do not act while it is up: a tap there
    // lands on the scrim, which skips.
    func testATapBesideTheCardSkipsWithoutActing() {
        launch(["-HINT", "editor-tools"])
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        // A modal card reaches accessibility as an alert: VoiceOver stays
        // on it. (Snapshots still list the covered tools, so tap by place.)
        XCTAssertEqual(intro.elementType, .alert, "the card is modal for VoiceOver")
        let toolBar = CGVector(dx: intro.frame.midX, dy: intro.frame.maxY + 50)
        app.coordinate(withNormalizedOffset: .zero).withOffset(toolBar).tap()
        waitUntilGone(intro)
        XCTAssertFalse(app.descendants(matching: .any)["canvas.textEditor"].exists,
                       "the Text tool behind the scrim did not fire")
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
