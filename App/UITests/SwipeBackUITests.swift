import XCTest

/// #161: an edge swipe goes back from the screens pushed over Home, as their
/// top-left back button does.
final class SwipeBackUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func swipeBackFromTheEdge() {
        let window = app.windows.firstMatch
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
    }

    private func assertBackOnHome(_ screen: String) {
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5),
                      "swiping from the edge left \(screen)")
        XCTAssertTrue(app.buttons["Start a memory"].isHittable, "Home is showing, not mid-transition")
    }

    func testSwipeGoesBackFromSettings() {
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        swipeBackFromTheEdge()
        assertBackOnHome("Settings")
    }

    func testSwipeGoesBackFromTheStarJar() {
        app.buttons["home.starJar"].tap()
        XCTAssertTrue(app.staticTexts["Star jar"].waitForExistence(timeout: 5))
        swipeBackFromTheEdge()
        assertBackOnHome("the star jar")
    }

    func testSwipeOnHomeLeavesHomeUsable() {
        swipeBackFromTheEdge()
        app.buttons["home.starJar"].tap()
        XCTAssertTrue(app.staticTexts["Star jar"].waitForExistence(timeout: 5),
                      "a swipe on the root screen does not freeze navigation")
    }
}
