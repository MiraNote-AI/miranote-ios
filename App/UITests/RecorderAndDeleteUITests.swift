import XCTest

/// Handoff screens 08 and 22: the live recording bar can throw the take
/// away, and an element dropped below the canvas is deleted (one tap from
/// undone).
final class RecorderAndDeleteUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        app.buttons["Start a memory"].tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testDiscardThrowsTheTakeAway() {
        XCTAssertTrue(app.buttons["mode.voice"].waitForExistence(timeout: 5))
        app.buttons["mode.voice"].tap()
        app.buttons["recorder.record"].tap()
        let discard = app.buttons["recorder.discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recorder.stop"].exists)

        discard.tap()
        let stop = app.buttons["recorder.stop"]
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: stop)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["recorder.record"].exists, "back to the dock, not re-armed")
        XCTAssertFalse(app.buttons["recorder.keep"].exists, "no review: the take is gone")
        XCTAssertFalse(app.staticTexts["Add a note"].exists, "and no marker was placed")
    }

    func testDroppingBelowTheCanvasDeletesThenUndoRestores() {
        addTextBlock("drop me in the bin")
        let title = app.staticTexts["drop me in the bin"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        // The tool bar sits below the canvas: the delete zone.
        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let bin = app.buttons["mode.voice"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.08, thenDragTo: bin)

        let undo = app.buttons["toast.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(title.exists)
        XCTAssertFalse(app.descendants(matching: .any)["canvas.deleteZone"].exists, "the zone leaves with the drag")

        undo.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }

    private func addTextBlock(_ text: String) {
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text)
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }
}
