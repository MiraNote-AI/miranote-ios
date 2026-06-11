import XCTest

/// UI regression tests for the v1 bug classes that unit tests cannot see
/// (issue #5): Save wiping the canvas via a rebuilt view model, and the
/// long-press insert menu appearing offset from the touch point.
final class MiraNoteUITests: XCTestCase {
    private var app: XCUIApplication!

    private let emptyStateHint =
        "No collections yet. Start your first memory and it will live here."

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // AC4 / decision D3: the hint is the only guidance in v1.
    func testEmptyStateHintShownOnFirstLaunch() {
        XCTAssertTrue(app.staticTexts[emptyStateHint].waitForExistence(timeout: 5))
    }

    // AC2 regression: in v1, Save triggered a Home re-render that rebuilt
    // the canvas view model and wiped the items; a second Save then
    // overwrote the filed memory with the blank canvas.
    func testSaveKeepsCanvasAndFilesCollection() {
        app.buttons["Start a memory"].tap()

        let textPill = app.buttons["text"]
        XCTAssertTrue(textPill.waitForExistence(timeout: 5))
        textPill.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Hello memory")
        app.buttons["Done"].tap()

        let canvasText = app.staticTexts["Hello memory"]
        XCTAssertTrue(canvasText.waitForExistence(timeout: 5))

        app.buttons["Save"].tap()
        XCTAssertTrue(
            canvasText.waitForExistence(timeout: 3),
            "canvas content must survive Save"
        )

        // Back to Home: the memory is filed once and the hint is gone.
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["My memories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 memories"].exists)
        XCTAssertFalse(app.staticTexts[emptyStateHint].exists)
    }

    // AC3 regression: in v1 the long-press location was measured in the
    // safe-area-ignoring background's local space, so the menu rendered
    // about a navigation-bar height below the finger.
    func testLongPressMenuAppearsAtTouchPoint() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))

        let window = app.windows.firstMatch
        let normalized = CGVector(dx: 0.68, dy: 0.32)
        window.coordinate(withNormalizedOffset: normalized).press(forDuration: 0.8)

        let menu = app.otherElements["canvas.insertMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))

        let pressPoint = CGPoint(
            x: window.frame.minX + window.frame.width * normalized.dx,
            y: window.frame.minY + window.frame.height * normalized.dy
        )
        let menuCenter = CGPoint(x: menu.frame.midX, y: menu.frame.midY)
        XCTAssertLessThan(
            abs(menuCenter.x - pressPoint.x), 40,
            "menu center x \(menuCenter.x) too far from press x \(pressPoint.x)"
        )
        XCTAssertLessThan(
            abs(menuCenter.y - pressPoint.y), 40,
            "menu center y \(menuCenter.y) too far from press y \(pressPoint.y)"
        )
    }
}
