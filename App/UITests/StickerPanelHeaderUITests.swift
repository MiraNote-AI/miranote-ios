import XCTest

/// The Sticker panel's header and ways in and out (#205): Home / Undo /
/// Save all greyed while it is open (E1A, F1A, F2A); a sticker tap places
/// it, closes the panel and leaves it selected (E2B); the Sticker tool
/// again or a tap on the page above the panel leaves (H1A); a made sticker
/// waiting keeps today's Cancel and holds the panel (H2).
final class StickerPanelHeaderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.sticker"].waitForExistence(timeout: 5))
        app.buttons["mode.sticker"].tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private var stickers: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "element.sticker")
    }

    private func generate(_ words: String) {
        let prompt = app.textFields["sticker.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText(words)
        app.buttons["sticker.generate.run"].tap()
    }

    /// E2B: a preset tap closes the panel; the new sticker is selected and
    /// the header is live again.
    func testAPresetLandsSelectedAndTheHeaderComesBack() {
        let food = app.buttons["sticker.tab.food"]
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        food.tap()
        let martini = app.buttons["sticker.preset.martini"]
        XCTAssertTrue(martini.waitForExistence(timeout: 5))
        martini.tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "the panel closed")
        XCTAssertTrue(stickers.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(canvasState()["selected"] as? String, stickerID(), "the preset lands selected")
        XCTAssertEqual(app.buttons["nav.leading"].label, "Home")
        XCTAssertTrue(app.buttons["nav.leading"].isEnabled)
        XCTAssertTrue(app.buttons["nav.trailing"].isEnabled)
    }

    /// E1A, F1A, F2A: Home, Undo and Save all greyed while the panel is open;
    /// no Add.
    func testThePanelsHeaderIsHomeUndoSaveAllGreyed() {
        XCTAssertTrue(app.buttons["sticker.tab.make"].waitForExistence(timeout: 5))
        let home = app.buttons["nav.leading"]
        XCTAssertEqual(home.label, "Home")
        XCTAssertFalse(home.isEnabled)
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled)
        XCTAssertEqual(app.buttons["nav.trailing"].label, "Save")
        XCTAssertFalse(app.buttons["nav.trailing"].isEnabled)
        XCTAssertFalse(app.buttons["Add"].exists, "no Add in the header")
    }

    /// H1A: the lit Sticker tool again closes the panel without placing.
    func testTheStickerToolAgainClosesThePanel() {
        XCTAssertTrue(app.textFields["sticker.prompt"].waitForExistence(timeout: 5))
        app.buttons["mode.sticker"].tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "back on the canvas")
        XCTAssertFalse(app.textFields["sticker.prompt"].exists)
        XCTAssertEqual(stickers.count, 0, "nothing placed")
    }

    /// H1A: a tap on the page above the panel closes it without placing.
    func testATapOnThePageAboveThePanelClosesIt() {
        XCTAssertTrue(app.staticTexts["Sticker"].waitForExistence(timeout: 5))
        let header = app.buttons["nav.leading"]
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: header.frame.maxY + 40)).tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "back on the canvas")
        XCTAssertEqual(stickers.count, 0, "nothing placed")
    }

    /// H2: while a made sticker waits, the leading pill is Cancel (Save and
    /// Undo stay greyed); neither the Sticker tool nor a page tap drops it.
    func testAWaitingMadeStickerKeepsCancelAndHoldsThePanel() {
        generate("a coffee cup")
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))
        let cancel = app.buttons["nav.leading"]
        XCTAssertEqual(cancel.label, "Cancel")
        XCTAssertTrue(cancel.isEnabled)
        XCTAssertFalse(app.buttons["nav.trailing"].isEnabled, "Save stays greyed")
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled)

        app.buttons["mode.sticker"].tap()
        XCTAssertTrue(app.staticTexts["Add the sticker you made first, or Cancel to let it go."]
            .waitForExistence(timeout: 3), "the tool says why it stays")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: cancel.frame.maxY + 40)).tap()
        sleep(1)
        XCTAssertTrue(any("sticker.result.0").exists, "the coffee cup still waits")
        XCTAssertFalse(app.miraComposer.exists, "still in the panel")
    }

    private func canvasState() -> [String: Any] {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        return (try? JSONSerialization.jsonObject(with: Data(probe.label.utf8))) as? [String: Any] ?? [:]
    }

    /// The first sticker on the page's id, from the canvas probe.
    private func stickerID() -> String? {
        let elements = canvasState()["elements"] as? [[String: Any]] ?? []
        return elements.first { $0["kind"] as? String == "sticker" }?["id"] as? String
    }
}
