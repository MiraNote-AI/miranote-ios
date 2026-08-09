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

    /// The seam the mock cannot prove: the app really sends the page map
    /// to :8003, a real model really picks an element and computes
    /// coordinates, and those coordinates really land on the canvas.
    ///
    /// Skipped unless MIRANOTE_LIVE_SEAM=1, because it needs the chatbot
    /// and image POCs running and spends real model calls.
    func testLiveBackendMovesARealElement() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MIRANOTE_LIVE_SEAM"] == "1",
            "needs live backends; set MIRANOTE_LIVE_SEAM=1"
        )
        let app = XCUIApplication()
        app.launchEnvironment["MIRANOTE_SCREEN"] = "canvas"
        app.launchEnvironment["MIRANOTE_CHAT_LIVE"] = "1"
        // Both channels: the app reads either the environment or the
        // matching UserDefaults key set by a launch argument.
        app.launchArguments += ["-MIRANOTE_CHAT_LIVE", "YES"]
        app.launch()

        let input = app.textFields["mira.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        // Deliberately outside MockChatService's vocabulary (it only
        // answers move/tidy/arrange/bigger/smaller). If this lands an
        // edit, a real model read the page map and chose the element --
        // the mock could not have produced it.
        input.typeText("put the photo behind everything else\n")

        let receipt = app.staticTexts["mira.receipt"]
        if !receipt.waitForExistence(timeout: 70) {
            // Report what IS on screen -- a reply card means Mira only
            // talked, a failure card means the keyword ladder claimed the
            // ask before it ever reached her. Both look identical to a
            // bare "no receipt".
            XCTFail("no receipt; on screen: " + app.staticTexts
                .allElementsBoundByIndex.prefix(8).map(\.label).joined(separator: " | "))
        }
        XCTAssertTrue(
            app.buttons["mira.revert"].exists,
            "a live edit is revertible like any other"
        )
    }
}
