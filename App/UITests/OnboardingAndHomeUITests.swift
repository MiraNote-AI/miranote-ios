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
        let intro = app.otherElements["onboarding.tools"]
        XCTAssertTrue(intro.waitForExistence(timeout: 5), "a first blank page introduces the tools")
        XCTAssertTrue(app.staticTexts["Create your way"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "tools onboarding"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["onboarding.background"].tap()
        XCTAssertFalse(intro.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["background.default"].waitForExistence(timeout: 5),
                      "the handoff flow goes on to the Background tool")
    }

    func testSkipJustCloses() {
        launch(["-HINT", "editor-tools"])
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap()
        XCTAssertFalse(app.otherElements["onboarding.tools"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["background.default"].exists)
        XCTAssertTrue(app.buttons["mode.text"].exists)
    }

    func testOtherUITestLaunchesNeverSeeIt() {
        launch([])
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["onboarding.tools"].exists)
    }
}
