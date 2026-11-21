import XCTest

/// Page background asks and the Background tool (handoff screen 05),
/// deterministic under -UITEST.
final class BackgroundUITests: XCTestCase {
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

    private func ask(_ words: String) {
        app.askMira(words)
    }

    private func openTool() {
        app.openBackground()
    }

    func testBackgroundAskPlacesViaChoices() {
        startMemory()
        ask("give this page a sunset background")
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "two candidates arrive")
        first.tap()
        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 5))
    }

    func testClearBackgroundReceipts() {
        startMemory()
        // On a default page there is nothing to clear, and the receipt says
        // so rather than claiming a change it cannot revert (#87).
        ask("remove the background")
        XCTAssertTrue(
            app.staticTexts["Already on the default background."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["mira.revert"].exists, "nothing changed, nothing to revert")

        app.openBackgroundRow("color")
        let lilac = app.buttons["background.color.#E6D9F0"]
        XCTAssertTrue(lilac.waitForExistence(timeout: 5))
        lilac.tap()
        app.closeBackground()

        ask("remove the background")
        XCTAssertTrue(app.staticTexts["Cleared the background."].waitForExistence(timeout: 8))
    }

    private var probe: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
    }

    private func probeShows(_ fragment: String, timeout: TimeInterval = 5) -> Bool {
        let shows = NSPredicate(format: "label CONTAINS %@", fragment)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shows, object: probe)],
                                timeout: timeout) == .completed
    }

    /// The tool is open: its row is in the tool bar's place.
    private var toolRow: XCUIElement { app.descendants(matching: .any)["background.row.tools"] }

    /// The canvas is back: the tool's row is gone and the Mira composer shows.
    private func assertBackOnTheCanvas(_ message: String) {
        XCTAssertTrue(app.backgroundSlotRows.firstMatch.waitForNonExistence(timeout: 5), message)
        XCTAssertTrue(app.buttons["mira.go"].waitForExistence(timeout: 5), "the canvas composer is back")
        XCTAssertTrue(app.buttons["mode.background"].exists, "the tool bar is back")
        XCTAssertFalse(app.buttons["mode.background"].isSelected, "the tool is closed")
    }

    // Owner, TestFlight 1.0(6): Apply with nothing typed was a dead button.
    // It closes the tool and keeps everything its rows applied.
    func testApplyWithNoWordsReturnsToTheCanvasKeepingThePicks() {
        startMemory()
        app.openBackgroundRow("paper")
        app.buttons["background.paper.grid"].tap()
        app.openBackgroundRow("color")
        app.buttons["background.color.#E6D9F0"].tap()
        let apply = app.buttons["background.apply"]
        XCTAssertTrue(apply.isEnabled, "Apply is never dead while the tool is open")
        apply.tap()

        assertBackOnTheCanvas("Apply closed the tool")
        XCTAssertTrue(probeShows("\"pageColor\":\"#E6D9F0\""), "the color stays: \(probe.label)")
        XCTAssertTrue(probeShows("\"paper\":\"grid\""), "the paper stays: \(probe.label)")
    }

    // While Apply paints, the page color controls and the sets rest: a
    // color or set picked or a hex typed then would wipe the paid painting
    // when it lands (#127 review, R5A). Paper stays usable. The painting
    // lands all the same.
    func testColorControlsRestWhileApplyPaints() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-GENERATE_DELAY", "8000"]
        app.launch()
        startMemory()
        // Painting from the Color row: its dots rest where they are.
        app.openBackgroundRow("color")
        app.paintBackground("a soft sunset glow")
        XCTAssertTrue(app.staticTexts["background.status"].waitForExistence(timeout: 3))
        for id in ["background.color.custom", "background.color.pick", "background.color.#E6D9F0"] {
            XCTAssertFalse(app.buttons[id].isEnabled, "\(id) rests while painting")
        }
        app.buttons["background.color.custom"].tap()
        XCTAssertFalse(app.buttons["Cancel"].waitForExistence(timeout: 1), "no color sheet opens")

        app.backToBackgroundItems()
        XCTAssertFalse(app.buttons["background.tool.sets"].isEnabled, "Sets rests while painting")
        XCTAssertFalse(app.buttons["background.tool.color"].isEnabled, "Color rests while painting")
        XCTAssertFalse(app.buttons["background.tool.tidy"].isEnabled, "Tidy rests while painting")
        XCTAssertTrue(app.buttons["background.tool.paper"].isEnabled, "Paper stays usable")
        app.openBackgroundRow("paper")
        app.buttons["background.paper.grid"].tap()
        XCTAssertTrue(probeShows("\"paper\":\"grid\""), "a paper applies while painting: \(probe.label)")
        XCTAssertTrue(app.staticTexts["background.status"].exists, "still painting")

        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 12))
        XCTAssertTrue(probeShows("\"backdropDescribes\":\"a soft sunset glow\""),
                      "the painting stays on the page: \(probe.label)")
        XCTAssertTrue(probeShows("\"paper\":\"grid\""), "and the paper under it: \(probe.label)")
    }

    // Stop takes Apply's spot: a double tap on Apply still paints.
    func testADoubleTapOnApplyDoesNotStopThePainting() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-GENERATE_DELAY", "3000"]
        app.launch()
        startMemory()
        openTool()
        let words = app.textFields["background.apply.input"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap()
        words.typeText("a soft sunset glow")
        // A tap on the page lowers the keyboard and keeps the tool.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["background.apply"].doubleTap()
        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 12),
                      "the painting landed")
    }

    // The color dots tap as 44 x 44 boxes.
    func testColorDotsHaveFullTapTargets() {
        startMemory()
        app.openBackgroundRow("color")
        for id in ["background.color.default", "background.color.#F4E0D1", "background.color.custom",
                   "background.color.pick"] {
            let dot = app.buttons[id]
            XCTAssertTrue(dot.waitForExistence(timeout: 5))
            XCTAssertEqual(dot.frame.width, 44, accuracy: 0.5, id)
            XCTAssertEqual(dot.frame.height, 44, accuracy: 0.5, id)
        }
    }

    // Stop gives the words back, the tool stays and nothing is painted.
    func testStopKeepsTheWordsAndPaintsNothing() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-GENERATE_DELAY", "4000"]
        app.launch()
        startMemory()
        openTool()
        let words = app.textFields["background.apply.input"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap()
        words.typeText("a soft sunset glow")
        let apply = app.buttons["background.apply"]
        apply.tap()
        XCTAssertTrue(app.staticTexts["background.status"].waitForExistence(timeout: 3))
        XCTAssertEqual(apply.label, "Stop")
        apply.tap()

        XCTAssertTrue(words.waitForExistence(timeout: 2), "the composer is back")
        XCTAssertEqual(words.value as? String, "a soft sunset glow", "the words are back")
        XCTAssertEqual(apply.label, "Apply")
        XCTAssertFalse(app.staticTexts["background.status"].exists, "no longer painting")
        XCTAssertTrue(probeShows("\"paintGlow\":\"\""), "the glow ended: \(probe.label)")
        XCTAssertTrue(toolRow.exists, "the tool stays open")
        // Past the painting's own time: nothing late lands.
        sleep(5)
        XCTAssertFalse(app.staticTexts["Set the page background."].exists, "nothing landed")
        XCTAssertFalse(app.buttons["mira.keep"].exists, "no receipt")
        XCTAssertTrue(probeShows("\"backdrop\":\"\""), "the page is untouched: \(probe.label)")
        XCTAssertTrue(app.buttons["background.tool.color"].isEnabled, "the rows are back")
    }

    // A painting that does not come says so over the tool's row, with the
    // words back for another try; the page is untouched.
    func testApplyFailureSaysSoOverTheRow() {
        startMemory()
        openTool()
        let words = app.textFields["background.apply.input"]
        words.tap()
        words.typeText("fail this one")
        app.buttons["background.apply"].tap()

        let notice = app.staticTexts["background.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 8), "the failure is said over the row")
        // The row's drawn top: its 40 pt Back's (its frame takes the caption in).
        let rowTop = app.buttons["background.back"].frame.midY - 20
        XCTAssertLessThanOrEqual(notice.frame.maxY, rowTop, "above the row (G25): \(notice.frame), row at \(rowTop)")
        XCTAssertTrue(toolRow.exists, "the tool stays open")
        XCTAssertEqual(words.value as? String, "fail this one", "the words are back")
        XCTAssertEqual(app.buttons["background.apply"].label, "Apply", "the composer is back to Apply")
        XCTAssertTrue(probeShows("\"paintGlow\":\"\""), "the glow ended: \(probe.label)")
        XCTAssertTrue(probeShows("\"backdrop\":\"\""), "the page is untouched: \(probe.label)")
        // The strip's failure shows only on the bare canvas: leave the tool
        // so this check could fail.
        app.buttons["background.back"].tap()
        assertBackOnTheCanvas("Back closed the tool")
        XCTAssertFalse(app.staticTexts["mira.failure"].waitForExistence(timeout: 2), "said once, over the row")
    }

    // The handoff draws nothing between the tool bar and the composer on the
    // canvas (screens 04, 05, 07, 22): no idle suggestion chips, even once
    // the page has words that used to summon them, and exactly 16 pt.
    // Quick actions return inside the Mira chat overlay (screen 06).
    func testIdleCanvasHasNoChipRowAboveTheComposer() {
        startMemory()
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lunch by the river")
        app.buttons["keyboard.done"].tap()

        let go = app.buttons["mira.go"]
        XCTAssertTrue(go.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mira.suggestion.Change the background"].exists)
        XCTAssertFalse(app.buttons["mira.suggestion.Add a soft title"].exists)

        // Hit frames reach 5 pt past the drawn 40/34 pt capsules; the Go
        // pill sits 10 below the composer's top edge.
        let toolBarBottom = app.buttons["mode.text"].frame.maxY - 5
        let composerTop = go.frame.minY + 5 - 10
        XCTAssertEqual(composerTop - toolBarBottom, 16, accuracy: 1)
    }
}

// MARK: Paper and page color

extension BackgroundUITests {
    /// The page wears `hex` ("" for the default backdrop).
    private func pageColorIs(_ hex: String) -> Bool { probeShows("\"pageColor\":\"\(hex)\"") }

    // Paper tiles and color dots apply in place, each one undo step;
    // Default gives the page back its default backdrop but keeps the paper,
    // and a tap on the chosen dot changes nothing.
    func testPaperTileAndSwatchApplyAndDefaultResets() {
        startMemory()
        app.openBackgroundRow("paper")
        let grid = app.buttons["background.paper.grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["background.paper.blank"].isSelected, "new pages start blank")
        XCTAssertTrue(pageColorIs(""), "on the default backdrop: \(probe.label)")
        grid.tap()
        XCTAssertTrue(grid.isSelected)

        app.openBackgroundRow("color")
        let lilac = app.buttons["background.color.#E6D9F0"]
        let byDefault = app.buttons["background.color.default"]
        XCTAssertTrue(byDefault.isSelected, "the row opens on Default")
        lilac.tap()
        XCTAssertTrue(lilac.isSelected)
        XCTAssertTrue(pageColorIs("#E6D9F0"), "the page wears the color: \(probe.label)")

        app.buttons["Undo"].tap()
        XCTAssertFalse(lilac.isSelected, "one undo takes the color off")
        XCTAssertTrue(byDefault.waitForSelection(), "and the row is back on Default")
        XCTAssertTrue(probeShows("\"paper\":\"grid\""), "and leaves the paper: \(probe.label)")

        lilac.tap()
        XCTAssertTrue(probeShows("\"pageColor\":\"#E6D9F0\""), "\(probe.label)")
        let depth = app.undoDepth
        lilac.tap()
        XCTAssertTrue(lilac.isSelected, "the chosen dot, tapped again, stays chosen")
        XCTAssertEqual(app.undoDepth, depth, "and records nothing")
        byDefault.tap()
        XCTAssertTrue(byDefault.isSelected, "Default resets")
        XCTAssertTrue(pageColorIs(""), "back on the default backdrop: \(probe.label)")
        app.openBackgroundRow("paper")
        XCTAssertTrue(grid.isSelected, "resetting the color keeps the paper")
    }

    // A swatch's hex typed in the Custom sheet (the tool's one hex field)
    // selects that swatch; an unfinished hex leaves the page as it was.
    func testHexEntrySetsThePageColor() {
        startMemory()
        app.openBackgroundRow("color")
        app.buttons["background.color.custom"].tap()
        let hex = app.textFields["background.colorSheet.hex"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        replace(hex, with: "d1e0f0")
        hex.typeText("\n")
        app.buttons["background.colorSheet.apply"].tap()
        XCTAssertTrue(app.buttons["background.color.#D1E0F0"].isSelected, "Sky, typed by hand")
        XCTAssertTrue(pageColorIs("#D1E0F0"), "\(probe.label)")

        app.buttons["background.color.custom"].tap()
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        XCTAssertEqual(hex.value as? String, "#D1E0F0", "the sheet opens on the page's hex")
        replace(hex, with: "not a color")
        hex.typeText("\n")
        XCTAssertTrue(pageColorIs("#D1E0F0") && hex.value as? String == "#D1E0F0", "nonsense previews nothing")
        app.buttons["background.colorSheet.apply"].tap()
        XCTAssertTrue(app.buttons["background.color.#D1E0F0"].isSelected, "nonsense changes nothing")
        XCTAssertTrue(pageColorIs("#D1E0F0"), "\(probe.label)")
    }

    // Custom opens the shared custom color sheet (screens 14 and 20) on the
    // page's color: a typed HEX previews on the page, Apply keeps it as one
    // undo step, and a tap outside drops a change.
    func testCustomSheetHexSetsThePageColor() {
        startMemory()
        app.openBackgroundRow("color")
        app.buttons["background.color.custom"].tap()
        let hex = app.textFields["background.colorSheet.hex"]
        let apply = app.buttons["background.colorSheet.apply"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5), "the custom color sheet is up")
        XCTAssertEqual(hex.value as? String, "#F6F4E8", "a default page starts the sheet on paper")
        replace(hex, with: "8B5962")
        hex.typeText("\n")
        XCTAssertTrue(pageColorIs("#8B5962"), "the page previews the typed color: \(probe.label)")
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5), "Apply closes the sheet")
        XCTAssertTrue(pageColorIs("#8B5962"), "and keeps the color: \(probe.label)")
        app.buttons["Undo"].tap()
        XCTAssertTrue(pageColorIs(""), "one undo step takes it off: \(probe.label)")

        app.buttons["background.color.custom"].tap()
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        replace(hex, with: "112233")
        hex.typeText("\n")
        XCTAssertTrue(pageColorIs("#112233"), "\(probe.label)")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5), "a tap outside closes the sheet")
        XCTAssertTrue(pageColorIs(""), "and drops the change: \(probe.label)")
        XCTAssertTrue(app.descendants(matching: .any)["background.row.color"].exists, "the color row stays")
    }

    // Pick goes straight to the eyedropper over the page; its Cancel leaves
    // the sheet up on the page's color.
    func testPickOpensTheEyedropper() {
        startMemory()
        app.openBackgroundRow("color")
        app.buttons["background.color.pick"].tap()
        let page = app.descendants(matching: .any)["background.colorSheet.pick.page"]
        XCTAssertTrue(page.waitForExistence(timeout: 5), "the page to sample from")
        app.buttons["background.colorSheet.pick.cancel"].tap()
        XCTAssertTrue(app.buttons["background.colorSheet.apply"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["background.colorSheet.hex"].value as? String, "#F6F4E8")
    }

    private func replace(_ textField: XCUIElement, with text: String) {
        textField.tap()
        let current = (textField.value as? String) ?? ""
        textField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 1))
        textField.typeText(text)
    }
}
