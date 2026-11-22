import XCTest

/// Walks the Background tool through its levels (demo3 S2-S3) and
/// photographs each one, on whichever phone runs it: the tool bar and the
/// tool's four items must fit every width (#162). The photos ride along as
/// test attachments; with SHOTS_DIR set (TEST_RUNNER_SHOTS_DIR for
/// xcodebuild) they are also written there.
final class BackgroundDesignShotsUITests: XCTestCase {
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

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? screenshot.pngRepresentation.write(
                to: URL(fileURLWithPath: directory).appendingPathComponent("app-\(name).png")
            )
        }
    }

    /// Each button sits whole on screen, inside the screen's side margins.
    private func assertFits(_ ids: [String], _ what: String) {
        let screen = app.frame
        for id in ids {
            let frame = app.buttons[id].frame
            XCTAssertGreaterThanOrEqual(frame.minX, screen.minX, "\(what): \(id) starts on screen")
            XCTAssertLessThanOrEqual(frame.maxX, screen.maxX, "\(what): \(id) ends on screen")
            XCTAssertGreaterThanOrEqual(frame.width, 44, "\(what): \(id) is a full tap target")
        }
    }

    func testWalkThroughTheBackgroundLevels() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Sunday at the lake")
        app.buttons["keyboard.done"].tap()
        // Nothing selected: the page at rest (S1).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        XCTAssertTrue(app.buttons["mode.background"].waitForExistence(timeout: 5))
        assertFits(["mode.background", "mode.layout", "mode.voice", "mode.text", "mode.image", "mode.sticker"],
                   "the tool bar")
        shot("bg-1-toolbar")

        app.openBackground()
        assertFits(["background.back", "background.tool.sets", "background.tool.color", "background.tool.paper",
                    "background.tool.tidy"], "the four items")
        shot("bg-2-items")

        app.openBackgroundRow("color")
        shot("bg-3-color")
        app.openBackgroundRow("sets")
        shot("bg-4-sets")
        app.openBackgroundRow("paper")
        shot("bg-5-paper")
    }

    /// Mira paints (demo3 S4): typing in the Apply field, the working
    /// composer, the receipt on the card's foot, then the Color row.
    func testWalkThroughMiraPainting() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-GENERATE_DELAY", "5000"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Sunday at the lake")
        app.buttons["keyboard.done"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()

        app.openBackground()
        let words = app.textFields["background.apply.input"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap()
        words.typeText("soft watercolor sky")
        shot("bg-6-typing")
        app.buttons["background.apply"].tap()
        sleep(1)
        shot("bg-7-painting")
        XCTAssertTrue(app.buttons["mira.keep"].waitForExistence(timeout: 12), "the painting landed")
        shot("bg-8-receipt")
        app.openBackgroundRow("color")
        shot("bg-9-painted")
    }
}
