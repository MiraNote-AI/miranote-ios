import XCTest

/// Mira paints the page from the Background tool (#205 R5A, F4A, Q1A):
/// the card holds still under Apply's keyboard, the glow while she works,
/// and the receipt that floats on the card's foot while the row stays.
final class BackgroundPaintUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func startMemory() {
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    private func openTool() {
        app.openBackground()
    }

    private var probe: XCUIElement { app.canvasProbe }

    private func probeShows(_ fragment: String, timeout: TimeInterval = 5) -> Bool {
        let shows = NSPredicate(format: "label CONTAINS %@", fragment)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shows, object: probe)],
                                timeout: timeout) == .completed
    }

    /// The tool is open: its row is in the tool bar's place.
    private var toolRow: XCUIElement { app.descendants(matching: .any)["background.row.tools"] }

    // The tool's composer is "Apply to this page": the typed words ask Mira
    // to paint a backdrop. While she paints the composer is her working bar,
    // "Painting..." with Stop, and a glow breathes on the page (R5A); the
    // painting lands on the page and its receipt floats on the card's foot
    // while the tool's row stays (F4A, Q1A).
    // Owner, TestFlight 1.0(5): Apply did nothing visible -- the painting
    // waited as thumbnails for a second pick. With the painting taking its
    // time, as the live backend does.
    func testApplyToThisPagePaintsThePage() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-GENERATE_DELAY", "3000"]
        app.launch()
        startMemory()
        openTool()
        app.paintBackground("a soft sunset glow")

        let status = app.staticTexts["background.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3), "the composer says Mira is painting")
        XCTAssertEqual(status.label, "Painting...")
        XCTAssertFalse(app.textFields["background.apply.input"].exists, "the working bar in the composer's place")
        XCTAssertTrue(toolRow.exists, "the tool stays open while painting")
        XCTAssertEqual(app.buttons["background.apply"].label, "Stop", "the work can be stopped")
        XCTAssertTrue(probeShows("\"paintGlow\":\"breathing\""), "a glow breathes on the page: \(probe.label)")
        XCTAssertFalse(app.descendants(matching: .any)["background.notice"].exists, "no caption over the row")

        let receipt = app.staticTexts["Set the page background."]
        XCTAssertTrue(receipt.waitForExistence(timeout: 12), "Apply's painting landed")
        XCTAssertTrue(toolRow.exists, "the tool's row stays under the receipt")
        XCTAssertFalse(app.buttons["mode.background"].exists, "the tool bar is not back")
        XCTAssertLessThan(app.buttons["mira.keep"].frame.maxY, app.buttons["background.back"].frame.minY,
                          "the receipt floats above the row, on the card's foot")
        XCTAssertTrue(app.buttons["background.apply"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons["background.apply"].label, "Apply", "the composer is back to Apply")
        XCTAssertTrue(probeShows("\"paintGlow\":\"\""), "the glow ended: \(probe.label)")
        XCTAssertFalse(app.buttons["mira.imageChoice.0"].exists, "no second pick")
        XCTAssertTrue(probeShows("\"backdropDescribes\":\"a soft sunset glow\""),
                      "the page wears the new painting: \(probe.label)")
        XCTAssertTrue(app.buttons["mira.revert"].exists, "Revert / Keep on the card")
    }

    // Painting from the Sets row: its cards rest where they are, since a
    // set would wipe the painting when it lands (R5A).
    func testTheSetsRowRestsWhilePainting() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-GENERATE_DELAY", "4000"]
        app.launch()
        startMemory()
        app.openBackgroundRow("sets")
        app.paintBackground("a soft sunset glow")
        XCTAssertTrue(app.staticTexts["background.status"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["background.set.didot-cardo"].isEnabled, "the sets rest while painting")
        XCTAssertTrue(app.buttons["mira.keep"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["background.set.didot-cardo"].isEnabled, "and are back once it landed")
    }

    // A tap on any item of the row is Keep (F4A): the receipt goes, the
    // painting stays, and the item does its own work -- Color opens its row
    // on the Painted cell.
    func testATapOnARowItemKeepsThePainting() {
        startMemory()
        openTool()
        app.paintBackground("a soft sunset glow")
        XCTAssertTrue(app.buttons["mira.keep"].waitForExistence(timeout: 12))
        let backdrop = app.backdrop
        XCTAssertFalse(backdrop.isEmpty, "the page wears the painting")

        app.buttons["background.tool.color"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["background.row.color"].waitForExistence(timeout: 5),
                      "Color opened its row")
        XCTAssertTrue(app.buttons["mira.keep"].waitForNonExistence(timeout: 3), "the tap kept the painting")
        XCTAssertEqual(app.backdrop, backdrop, "the painting stays")
        XCTAssertTrue(app.buttons["background.color.painted"].waitForSelection(), "the Painted cell is chosen")
    }

    // Revert on the floating receipt takes the painting back; the tool stays.
    func testRevertOnTheReceiptTakesThePaintingBack() {
        startMemory()
        openTool()
        app.paintBackground("a soft sunset glow")
        let revert = app.buttons["mira.revert"]
        XCTAssertTrue(revert.waitForExistence(timeout: 12))
        revert.tap()
        XCTAssertTrue(revert.waitForNonExistence(timeout: 3))
        XCTAssertTrue(probeShows("\"backdrop\":\"\""), "the painting is gone: \(probe.label)")
        XCTAssertTrue(toolRow.exists, "the tool stays open")
    }

    // Typing a new painting moves on from the last one's receipt: the
    // keyboard would cover it.
    func testTypingAgainKeepsTheLastPainting() {
        startMemory()
        openTool()
        app.paintBackground("a soft sunset glow")
        XCTAssertTrue(app.buttons["mira.keep"].waitForExistence(timeout: 12))
        app.textFields["background.apply.input"].tap()
        XCTAssertTrue(app.buttons["mira.keep"].waitForNonExistence(timeout: 3), "the receipt was kept")
        XCTAssertTrue(probeShows("\"backdropDescribes\":\"a soft sunset glow\""), "the painting stays")
    }

    // Under Reduce Motion the scene asks for the glow's still tint, not
    // the breathing one.
    func testUnderReduceMotionThePaintingGlowIsStill() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-REDUCE_MOTION", "-GENERATE_DELAY", "3000"]
        app.launch()
        startMemory()
        openTool()
        app.paintBackground("a soft sunset glow")
        XCTAssertTrue(probeShows("\"paintGlow\":\"still\""), "a still tint: \(probe.label)")
        XCTAssertTrue(app.buttons["mira.keep"].waitForExistence(timeout: 12))
        XCTAssertTrue(probeShows("\"paintGlow\":\"\""), "gone once it landed: \(probe.label)")
    }

    // Closing the tool mid-painting: the glow ends with it, the turn runs on
    // in the canvas strip (its own Stop) and lands with the receipt there.
    func testClosingTheToolMidPaintingHandsTheTurnToTheStrip() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-GENERATE_DELAY", "3000"]
        app.launch()
        startMemory()
        openTool()
        app.paintBackground("a soft sunset glow")
        XCTAssertTrue(app.staticTexts["background.status"].waitForExistence(timeout: 3))
        app.buttons["background.back"].tap()
        XCTAssertTrue(app.buttons["mira.stop"].waitForExistence(timeout: 3), "the strip's Stop")
        XCTAssertTrue(probeShows("\"paintGlow\":\"\""), "the glow ended with the tool: \(probe.label)")
        XCTAssertTrue(app.buttons["mira.keep"].waitForExistence(timeout: 12), "it lands with the receipt")
        XCTAssertTrue(probeShows("\"backdropDescribes\":\"a soft sunset glow\""), probe.label)
    }

    /// The card's top and height, from the probe.
    private var board: [Double] {
        guard let data = probe.label.data(using: .utf8),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let board = state["board"] as? [Double] else { return [] }
        return board
    }

    // Typing in Apply, the card keeps its size and place; the row and the
    // composer ride over its foot, on the keyboard (final 42). When the
    // keyboard goes they go back down.
    func testTheCardHoldsStillUnderTheApplyKeyboard() {
        startMemory()
        openTool()
        let before = board
        XCTAssertEqual(before.count, 2, probe.label)
        // The pill's frame: the field's own height changes with its focus.
        let apply = app.buttons["background.apply"]
        let restingY = apply.frame.minY
        app.textFields["background.apply.input"].tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertEqual(board, before, "the card neither shrinks nor moves")
        XCTAssertLessThan(apply.frame.maxY, keyboard.frame.minY, "the composer sits on the keyboard")
        XCTAssertLessThan(apply.frame.minY, restingY - 100, "it rode up with the keyboard")
        XCTAssertLessThanOrEqual(app.buttons["background.back"].frame.maxY, apply.frame.minY,
                                 "the row rides above the composer")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        sleep(1)
        XCTAssertEqual(apply.frame.minY, restingY, accuracy: 0.5, "the composer is back in its place")
        XCTAssertEqual(board, before)
    }
}
