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

    /// The panel records no steps of its own (presets and favorites leave
    /// it as they place): its header Undo is off, never the canvas-wide
    /// undo reaching under the scrim.
    func testThePanelsHeaderUndoLeavesTheCanvasAlone() {
        app.buttons["nav.leading"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Dinner with Mom")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["editor.undo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.undo"].isEnabled, "the block can be undone from the canvas")

        app.buttons["mode.sticker"].tap()
        XCTAssertTrue(app.buttons["sticker.tab.make"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled, "the panel's Undo would take the block away")
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

    /// A photo becomes a sticker with no edge (team decision 2026-10-24):
    /// the cut is what shows, Outline is not lit and there is nothing to
    /// undo. It used to push an outlined look on top of the cut.
    func testAPhotoBecomesAStickerWithNoEdge() {
        app.buttons["nav.leading"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        let photo = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        app.buttons["nav.trailing"].tap()
        // Placed photos arrive unselected; the shortcut needs one selected.
        photo.tap()

        app.buttons["mode.sticker"].tap()
        let fromPhoto = app.buttons["sticker.fromPhoto"]
        XCTAssertTrue(fromPhoto.waitForExistence(timeout: 5), "the selected photo's shortcut shows")
        fromPhoto.tap()
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["sticker.style.cutout"].isSelected, "the plain cut is the showing look")
        XCTAssertFalse(app.buttons["sticker.style.outline"].isSelected, "no edge was added")
        XCTAssertFalse(app.buttons["sticker.undo"].isEnabled, "no look sits on top of the cut")
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

    /// Owner, 2026-10-19: "Add to page" under the result, within the thumb's
    /// reach, puts the showing sticker on the page in view -- selected, one
    /// undo step, the toast's Undo takes it back. The header has no Add then.
    func testAddToPagePlacesTheShowingResultInView() {
        generate("a coffee cup")
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["nav.trailing"].exists, "no second Add in the header")
        let add = app.buttons["sticker.addToPage"]
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        add.tap()

        XCTAssertTrue(stickers.firstMatch.waitForExistence(timeout: 5), "it landed")
        XCTAssertEqual(stickers.count, 1)
        XCTAssertTrue(app.buttons["Save"].isHittable, "back on the canvas")
        // It lands selected: the probe's selection is the new sticker.
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let state = (try? JSONSerialization.jsonObject(with: Data(probe.label.utf8))) as? [String: Any] ?? [:]
        let sticker = (state["elements"] as? [[String: Any]] ?? []).first { $0["kind"] as? String == "sticker" }
        XCTAssertNotNil(sticker)
        XCTAssertEqual(state["selected"] as? String, sticker?["id"] as? String, "the sticker lands selected")
        let undo = app.buttons["toast.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(stickers.firstMatch.waitForNonExistence(timeout: 3), "Undo takes it back, in one step")
    }

    /// The canvas keeps its scroll across the panel's round trip (owner,
    /// 2026-10-19): looking further down a long page, the sticker lands in
    /// the part that was showing, and the page is still there.
    func testAStickerAddedFurtherDownLandsWhereThePageStood() {
        app.buttons["nav.leading"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Top line" + String(repeating: "\n", count: 30) + "Bottom line")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["keyboard.done"].waitForNonExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)).tap()

        let save = app.buttons["Save"]
        let toolBar = app.buttons["mode.text"]
        let block = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Top line'")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.7))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.25)))
        }
        let scrolledTop = block.frame.minY
        XCTAssertLessThan(scrolledTop, save.frame.maxY - 100, "the page is scrolled well down")

        app.buttons["mode.sticker"].tap()
        generate("a coffee cup")
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))
        app.buttons["sticker.addToPage"].tap()
        let sticker = stickers.firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 5))
        sleep(1)

        XCTAssertEqual(block.frame.minY, scrolledTop, accuracy: 2, "the page came back where it stood")
        XCTAssertGreaterThan(sticker.frame.minY, save.frame.maxY, "the sticker is in view, below the header")
        XCTAssertLessThan(sticker.frame.maxY, toolBar.frame.minY, "and above the tool bar")
    }

    /// With a made sticker showing, the sheet stays under the header: Cancel
    /// is the only way to let the sticker go (#127 review: on a 375 x 667
    /// phone the 500 pt sheet covered it). Run on the small phone too.
    func testTheMadeStickerSheetLeavesTheHeaderInView() {
        generate("a coffee cup")
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))
        sleep(1)
        let cancel = app.buttons["nav.leading"]
        XCTAssertTrue(cancel.isHittable, "Cancel is in view")
        XCTAssertGreaterThan(app.staticTexts["Sticker"].frame.minY, cancel.frame.maxY,
                             "the sheet starts below the header")
        XCTAssertTrue(app.buttons["sticker.addToPage"].isHittable, "Add to page still fits")
    }

    /// A tap on the made sticker adds it, as the pill does.
    func testATapOnTheResultAddsIt() {
        generate("a coffee cup")
        let result = any("sticker.result.0")
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
        XCTAssertTrue(stickers.firstMatch.waitForExistence(timeout: 5))
    }

    /// The hop is never waited on: Add lands the sticker within a moment,
    /// draggable at once.
    func testTheAddedStickerMovesRightAway() {
        generate("a coffee cup")
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))
        app.buttons["sticker.addToPage"].tap()
        let sticker = stickers.firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 2))
        let before = sticker.frame
        sticker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25)))
        XCTAssertGreaterThan(abs(sticker.frame.midY - before.midY), 40, "it moved under the finger")
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
        sleep(1)
        XCTAssertEqual(stickers.count, 0, "nothing lands")
        app.buttons["mode.sticker"].tap()
        XCTAssertTrue(app.textFields["sticker.prompt"].waitForExistence(timeout: 5))
        XCTAssertFalse(any("sticker.result.0").exists, "the made sticker is gone for good")
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
