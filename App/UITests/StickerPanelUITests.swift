import XCTest

/// The Sticker panel's handoff states (screens 30-35): presets place on a
/// tap, a made sticker restyles with its own undo and redo, and the header
/// Add hands the showing one to the canvas.
final class StickerPanelUITests: XCTestCase {
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

    func testAPresetFromTheFoodSetPlacesOnATap() {
        let food = app.buttons["sticker.tab.food"]
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        food.tap()
        XCTAssertTrue(food.isSelected)
        let martini = app.buttons["sticker.preset.martini"]
        XCTAssertTrue(martini.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sticker.preset.ramen"].exists, "the handoff's food set is bundled")

        martini.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5), "back on the canvas")
        XCTAssertTrue(stickers.firstMatch.waitForExistence(timeout: 5), "the preset landed")
        XCTAssertEqual(stickers.count, 1)
    }

    func testGeneratingShowsTheSpinnerThenTheResult() {
        generate("a cup, slowly")
        XCTAssertTrue(any("sticker.generating").waitForExistence(timeout: 3), "the generating spinner shows")
        XCTAssertFalse(app.buttons["sticker.style.outline"].isEnabled, "styles wait for a sticker")
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["sticker.style.outline"].isEnabled)
    }

    func testStylesStepBackAndForward() {
        generate("a coffee cup")
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))
        let undo = app.buttons["sticker.undo"]
        let redo = app.buttons["sticker.redo"]
        XCTAssertFalse(undo.isEnabled, "nothing to undo on a fresh sticker")

        let outline = app.buttons["sticker.style.outline"]
        outline.tap()
        let styled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: outline)
        XCTAssertEqual(XCTWaiter().wait(for: [styled], timeout: 5), .completed, "Outline is the showing look")
        XCTAssertTrue(undo.isEnabled)

        undo.tap()
        XCTAssertFalse(outline.isSelected, "undo shows the sticker as it came")
        XCTAssertTrue(redo.isEnabled)
        redo.tap()
        XCTAssertTrue(outline.isSelected, "redo brings the outline back")
        XCTAssertFalse(redo.isEnabled)
    }

    func testAddPlacesTheShowingResultWhereTheCanvasIsTapped() {
        generate("a coffee cup")
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))
        let add = app.buttons["nav.trailing"]
        XCTAssertEqual(add.label, "Add")
        add.tap()

        XCTAssertTrue(app.staticTexts["canvas.place.hint"].waitForExistence(timeout: 5))
        XCTAssertEqual(stickers.count, 0, "nothing lands before the canvas tap")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        XCTAssertTrue(stickers.firstMatch.waitForExistence(timeout: 5), "the tap placed it")
    }

    func testFavoriteFilesTheShowingSticker() {
        generate("a coffee cup")
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))
        app.buttons["sticker.favorite"].tap()
        XCTAssertFalse(app.buttons["sticker.favorite"].isEnabled, "saved once")

        app.buttons["sticker.tab.favorites"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.item.'"))
        XCTAssertTrue(saved.firstMatch.waitForExistence(timeout: 5), "the favorite shows in the grid")
    }

    // A made sticker waiting to be added is not dropped by a preset or a
    // favorite tap (regression of #93): those wait, and say why.
    func testAPresetTapNeverDropsAMadeSticker() {
        generate("a coffee cup")
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))
        app.buttons["sticker.favorite"].tap()

        app.buttons["sticker.tab.food"].tap()
        let martini = app.buttons["sticker.preset.martini"]
        XCTAssertTrue(martini.waitForExistence(timeout: 5))
        XCTAssertFalse(martini.isEnabled, "presets wait for the made sticker")
        XCTAssertTrue(any("sticker.waiting").exists, "and say why")
        martini.tap()
        app.buttons["sticker.tab.favorites"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.item.'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertFalse(saved.isEnabled, "so do favorites")
        saved.tap()

        app.buttons["sticker.tab.make"].tap()
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 5), "the coffee cup still waits")
        XCTAssertEqual(stickers.count, 0, "nothing was placed meanwhile")
    }

    func testCancelDropsTheResult() {
        generate("a coffee cup")
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))
        app.buttons["nav.leading"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["canvas.place.hint"].exists)
        XCTAssertEqual(stickers.count, 0)
    }

    /// #93 through the panel's own tool bar: a tap there leaves the panel,
    /// which would drop the made sticker with it.
    func testAToolBarTapNeverDropsAMadeSticker() {
        generate("a coffee cup")
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))

        app.buttons["mode.background"].tap()
        // Either the tap is refused (still in the panel) or the sticker
        // survives the round trip.
        if app.buttons["mode.sticker"].waitForExistence(timeout: 2), !any("sticker.result.0").exists {
            app.buttons["mode.sticker"].tap()
        }
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 5), "the made coffee cup still waits")
    }
}
