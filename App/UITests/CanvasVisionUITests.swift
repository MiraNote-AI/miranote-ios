import XCTest

/// The canvas-vision loop running in the real app: type an ask, watch an
/// element actually move, revert it whole.
///
/// Runs against the DEBUG canvas catalog scene, whose MockChatService
/// answers a move ask with a canned page edit -- so this exercises the
/// whole wiring (input bar -> coordinator -> guards -> apply -> receipt)
/// with no backend.
final class CanvasVisionUITests: XCTestCase {
    private func launchCanvas() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MIRANOTE_SCREEN"] = "canvas"
        app.launch()
        return app
    }

    func testAskingMiraToMoveSomethingLandsAReceiptAndReverts() {
        let app = launchCanvas()

        let input = app.textFields["mira.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "the canvas ask bar is there")
        input.tap()
        // Return submits (the field's submitLabel is .go). Tapping a
        // button named "Go" is ambiguous -- the keyboard has one too.
        input.typeText("move the title to the top\n")

        let receipt = app.staticTexts["mira.receipt"]
        XCTAssertTrue(
            receipt.waitForExistence(timeout: 10),
            "a canvas edit shows the Keep-pattern receipt"
        )
        XCTAssertEqual(receipt.label, "Moved the title.")

        // The escape hatch the receipt promises must be there.
        XCTAssertTrue(app.buttons["mira.revert"].exists, "the receipt offers Revert")
        app.buttons["mira.revert"].tap()
        XCTAssertFalse(
            app.buttons["mira.revert"].waitForExistence(timeout: 3),
            "reverting dismisses the receipt"
        )
    }
}
