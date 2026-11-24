import XCTest

/// #161: an edge swipe goes back from the screens pushed over Home, as their
/// top-left back button does. On Home, with nothing to go back to, it fires
/// nothing; a tap where it ends still does (#254).
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
        // It runs across the ask bar (#247).
        XCTAssertFalse(app.buttons["chat.home"].waitForExistence(timeout: 1), "the swipe did not open the chat")
        app.buttons["home.starJar"].tap()
        XCTAssertTrue(app.staticTexts["Star jar"].waitForExistence(timeout: 5),
                      "a swipe on the root screen does not freeze navigation")
    }

    // MARK: Home has nothing to go back to (#254)

    /// A point on the screen, in points from its top-left corner.
    private func point(_ left: CGFloat, _ top: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: left, dy: top))
    }

    /// Where the short swipes end and the taps land: on the bar's star, and
    /// as far into the left card.
    private var starX: CGFloat { app.homeAsk.frame.minX + 18 }

    private var leftCard: XCUIElement { app.buttons["collection.Daily Log"] }

    /// A short swipe from the left screen edge, at the height of `row`.
    private func swipeFromTheEdge(to left: CGFloat, along row: CGRect) {
        point(2, row.midY).press(forDuration: 0.05, thenDragTo: point(left, row.midY))
    }

    private func assertStillHome(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(app.buttons["chat.home"].waitForExistence(timeout: 2), "\(message): no chat",
                       file: file, line: line)
        XCTAssertFalse(app.buttons["note.add"].exists, "\(message): no journal", file: file, line: line)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "\(message): no keyboard", file: file, line: line)
        XCTAssertTrue(app.buttons["Start a memory"].isHittable, "\(message): Home is on screen",
                      file: file, line: line)
    }

    func testAShortSwipeFromTheEdgeToTheStarOpensNothing() {
        swipeFromTheEdge(to: starX, along: app.homeAsk.frame)
        assertStillHome("a swipe from the edge that ends on the star")
    }

    func testAShortSwipeFromTheEdgeToTheLeftCardOpensNothing() {
        swipeFromTheEdge(to: starX, along: leftCard.frame)
        assertStillHome("a swipe from the edge that ends on the left card")
    }

    func testALongSwipeFromTheEdgeAcrossTheAskBarOpensNothing() {
        swipeFromTheEdge(to: app.frame.width * 0.9, along: app.homeAsk.frame)
        assertStillHome("a swipe from the edge across the bar")
    }

    /// Where the short swipe ends, a tap still opens the chat.
    func testATapOnTheStarOpensTheChat() {
        point(starX, app.homeAsk.frame.midY).tap()
        XCTAssertTrue(app.buttons["chat.home"].waitForExistence(timeout: 5), "a tap on the star opens the chat")
    }

    /// As from the bar's middle: the chat opens with its field focused.
    func testATapOnTheAskBarFocusesTheChatsField() {
        app.homeAsk.tap()
        XCTAssertTrue(app.chatField.waitForExistence(timeout: 5), "a tap on the bar opens the chat")
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"),
                                                object: app.chatField)
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 3), .completed, "the chat's field has the caret")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "the keyboard is up")
    }

    /// Where the short swipe ends, a tap still opens the journal.
    func testATapOnTheLeftCardOpensItsJournal() {
        point(starX, leftCard.frame.midY).tap()
        XCTAssertTrue(app.buttons["note.add"].waitForExistence(timeout: 5), "a tap on the left card opens its journal")
    }
}
