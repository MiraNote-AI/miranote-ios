import XCTest

/// The Background color row (P2A, D8A): a snap row of dots in a glass
/// tray -- Pick, Custom, the page's painting once Mira painted it, Default,
/// then the page colors -- that applies where it comes to rest.
final class BackgroundColorRowUITests: XCTestCase {
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

    private var probe: XCUIElement { app.canvasProbe }

    private func probeShows(_ fragment: String, timeout: TimeInterval = 5) -> Bool {
        let shows = NSPredicate(format: "label CONTAINS %@", fragment)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shows, object: probe)],
                                timeout: timeout) == .completed
    }

    /// The center marker's x: the middle of the tray beside Back.
    private var markerX: CGFloat {
        let row = app.descendants(matching: .any)["background.row.color"]
        return (app.buttons["background.row.back"].frame.maxX + 6 + row.frame.maxX) / 2
    }

    /// The page wears `hex` ("" for the default backdrop).
    private func pageColorIs(_ hex: String) -> Bool { probeShows("\"pageColor\":\"\(hex)\"") }

    // A swipe on the color row applies only where it comes to rest (Q5A):
    // one color, one undo step, and Undo takes the page straight back to
    // where it was, the row following without applying again (G24).
    func testASwipeAppliesOnceWhereTheColorRowSettles() {
        startMemory()
        app.openBackgroundRow("color")
        let byDefault = app.buttons["background.color.default"]
        XCTAssertTrue(byDefault.waitForExistence(timeout: 5))
        XCTAssertTrue(byDefault.isSelected)
        let depth = app.undoDepth
        XCTAssertGreaterThanOrEqual(depth, 0, "the probe reads the undo depth: \(probe.label)")

        app.descendants(matching: .any)["background.row.color"].swipeLeft(velocity: .slow)
        let swatches = ["#F6F4E8", "#F4E0D1", "#D6E3D4", "#D1E0F0", "#E6D9F0"]
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", ##".*"pageColor":"#[0-9A-F]{6}".*"##), object: probe)
        XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 5), .completed, "a color landed: \(probe.label)")
        sleep(1)
        let worn = swatches.filter { pageColorIs($0) }
        XCTAssertEqual(worn.count, 1, "the page wears one of the row's colors: \(probe.label)")
        let landed = app.buttons["background.color.\(worn.first ?? "")"]
        XCTAssertTrue(landed.isSelected, "the dot under the marker is chosen")
        XCTAssertEqual(landed.frame.midX, markerX, accuracy: 4, "and sits under the marker")
        XCTAssertEqual(app.undoDepth, depth + 1, "one undo step for the whole swipe")

        app.buttons["Undo"].tap()
        XCTAssertTrue(pageColorIs(""), "one undo, back on the default backdrop: \(probe.label)")
        XCTAssertTrue(byDefault.waitForSelection(), "Default is chosen again")
        sleep(1)
        XCTAssertEqual(byDefault.frame.midX, markerX, accuracy: 4, "the row scrolled back to it")
        XCTAssertTrue(pageColorIs(""), "and applied nothing on the way: \(probe.label)")
        XCTAssertEqual(app.undoDepth, depth)
    }

    // A painted backdrop is nobody's swatch: it has a cell of its own,
    // chosen. Any dot replaces it, and the painting's cell stays to bring
    // it back (D8A).
    func testASwatchReplacesAPaintedBackdrop() {
        startMemory()
        app.askMira("give this page a sunset background")
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 5))
        app.buttons["mira.keep"].tap()

        app.openBackgroundRow("color")
        XCTAssertFalse(probeShows("\"backdrop\":\"\"", timeout: 1), "the page wears a painting: \(probe.label)")
        let paper = app.buttons["background.color.#F6F4E8"]
        XCTAssertFalse(paper.isSelected, "a painted page wears no swatch")
        let painted = app.buttons["background.color.painted"]
        XCTAssertTrue(painted.isSelected, "it wears the painting")
        XCTAssertEqual(painted.frame.midX, markerX, accuracy: 4, "the row opened on it, under the marker")
        let painting = app.backdrop
        XCTAssertFalse(painting.isEmpty, "\(probe.label)")
        paper.tap()
        XCTAssertTrue(paper.isSelected, "the dot replaced the painting")
        XCTAssertTrue(probeShows("\"backdrop\":\"\""), "the painting is gone: \(probe.label)")
        XCTAssertTrue(pageColorIs("#F6F4E8"), "\(probe.label)")

        XCTAssertTrue(painted.exists, "the painting keeps its cell")
        painted.tap()
        XCTAssertTrue(painted.isSelected, "and comes back")
        XCTAssertTrue(probeShows("\"backdrop\":\"\(painting)\""), "the same painting: \(probe.label)")
        app.buttons["Undo"].tap()
        XCTAssertTrue(paper.waitForSelection(), "one undo, back on the color")
        XCTAssertTrue(probeShows("\"backdrop\":\"\""), "\(probe.label)")
    }
}
