import XCTest

/// #203: the Recents grid scrolls past its first three rows -- a swipe
/// that starts on a photo moves the grid, and far photos (past the first
/// page) can be picked and carried onto the page. -UITEST paints 120
/// samples, more than one page.
final class RecentsScrollUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        app.buttons["image.library.open"].tap()
        XCTAssertTrue(cell(0).waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func cell(_ index: Int) -> XCUIElement {
        any("image.library.photo.\(index)")
    }

    private var grid: XCUIElement { any("image.library.grid") }

    private var photos: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "element.image")
    }

    private func canvasState() -> [String: Any] {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let data = probe.label.data(using: .utf8) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Drags the grid up about a row at a time, slow and held so no fling
    /// overshoots, until `index`'s middle is inside it; at most 60 drags.
    private func scroll(to index: Int) {
        for _ in 0..<60 {
            let target = cell(index)
            if target.exists, grid.frame.insetBy(dx: 0, dy: 20).contains(
                CGPoint(x: target.frame.midX, y: target.frame.midY)) { return }
            let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -100)),
                        withVelocity: 150, thenHoldForDuration: 0.4)
        }
        XCTFail("photo \(index) never scrolled into the grid")
    }

    func testASwipeStartingOnAPhotoScrollsTheGrid() {
        let top = cell(0).frame.minY
        let row = cell(0).frame.height
        let start = cell(4).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -250)),
                    withVelocity: 1500, thenHoldForDuration: 0.1)
        sleep(1)
        XCTAssertTrue(!cell(0).exists || cell(0).frame.minY < top - row,
                      "the grid moved up by more than a row")
        XCTAssertEqual(photos.count, 0, "a swipe places nothing")
        XCTAssertEqual(canvasState()["photoDragging"] as? Bool, false, "a swipe carries nothing")
    }

    func testAPhotoPastTheFirstPageCanBePicked() {
        scroll(to: 100)
        cell(100).tap()
        XCTAssertTrue(cell(100).isSelected, "the far photo is picked")
        XCTAssertEqual(app.buttons["image.library.editing"].exists, true, "one pick offers Editing")
    }

    func testAFarPhotoDragsOntoThePage() {
        scroll(to: 40)
        let target = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width * 0.3, dy: grid.frame.minY - 160))
        cell(40).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.6, thenDragTo: target)
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"), object: photos)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 5), .completed, "the far photo landed")
        XCTAssertEqual(canvasState()["photoDragging"] as? Bool, false, "no carried photo is left")
    }
}
