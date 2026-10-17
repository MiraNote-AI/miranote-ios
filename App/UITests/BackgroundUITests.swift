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
        app.buttons["mode.background"].tap()
        XCTAssertTrue(app.staticTexts["background.title"].waitForExistence(timeout: 5), "the sheet is up")
    }

    private var previewColor: String { app.staticTexts["background.preview.color"].label }

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

        openTool()
        let lilac = app.buttons["background.color.#E6D9F0"]
        XCTAssertTrue(lilac.waitForExistence(timeout: 5))
        lilac.tap()
        app.buttons["mode.background"].tap()

        ask("remove the background")
        XCTAssertTrue(app.staticTexts["Cleared the background."].waitForExistence(timeout: 8))
    }

    // The tool's composer is "Apply to this page": the typed words ask Mira
    // to paint a backdrop, the sheet steps aside for the turn, and Apply
    // applies it. Owner, TestFlight 1.0(5): Apply did nothing visible --
    // the painting waited as thumbnails for a second pick. With the
    // painting taking its time, as the live backend does.
    func testApplyToThisPagePaintsThePage() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-GENERATE_DELAY", "3000"]
        app.launch()
        startMemory()
        openTool()
        let words = app.textFields["background.apply.input"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["background.apply"].isEnabled, "nothing to apply yet")
        words.tap()
        words.typeText("a soft sunset glow")
        app.buttons["background.apply"].tap()

        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 12),
                      "Apply's painting landed")
        XCTAssertFalse(app.staticTexts["background.title"].exists, "the sheet stepped aside for the turn")
        XCTAssertFalse(app.buttons["mira.imageChoice.0"].exists, "no second pick")
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        let painted = NSPredicate(format: "NOT (label CONTAINS '\"backdrop\":\"\"')")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: painted, object: probe)],
                                        timeout: 5), .completed, "the page wears no backdrop: \(probe.label)")
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

    // Paper tiles and color dots apply in place, each one undo step; the
    // chosen dot tapped again gives the page back its default backdrop but
    // keeps the paper.
    func testPaperTileAndSwatchApplyAndTheChosenDotResets() {
        startMemory()
        openTool()
        let grid = app.buttons["background.paper.grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["background.paper.blank"].isSelected, "new pages start blank")
        XCTAssertEqual(previewColor, "PREVIEW COLOR  \u{00B7}  DEFAULT")
        grid.tap()
        XCTAssertTrue(grid.isSelected)

        let lilac = app.buttons["background.color.#E6D9F0"]
        lilac.tap()
        XCTAssertTrue(lilac.isSelected)
        XCTAssertEqual(previewColor, "PREVIEW COLOR  \u{00B7}  #E6D9F0", "the preview wears the page color")

        app.buttons["Undo"].tap()
        XCTAssertFalse(lilac.isSelected, "one undo takes the color off")
        XCTAssertTrue(grid.isSelected, "and leaves the paper")

        lilac.tap()
        lilac.tap()
        XCTAssertFalse(lilac.isSelected, "the chosen dot, tapped again, resets")
        XCTAssertEqual(previewColor, "PREVIEW COLOR  \u{00B7}  DEFAULT")
        XCTAssertTrue(grid.isSelected, "resetting the color keeps the paper")
    }

    // The hex field takes any #RRGGBB; a swatch's hex selects that swatch,
    // and nonsense leaves the page as it was.
    func testHexEntrySetsThePageColor() {
        startMemory()
        openTool()
        let hex = app.textFields["background.hex"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        hex.tap()
        hex.typeText("d1e0f0\n")
        XCTAssertTrue(app.buttons["background.color.#D1E0F0"].isSelected, "Sky, typed by hand")
        XCTAssertEqual(hex.value as? String, "#D1E0F0", "the field shows the page's hex")

        // Return lowered the keyboard; focus again once it is gone.
        let keyboardGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 0"), object: app.keyboards)
        XCTAssertEqual(XCTWaiter().wait(for: [keyboardGone], timeout: 5), .completed)
        hex.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7) + "not a color\n")
        XCTAssertTrue(app.buttons["background.color.#D1E0F0"].isSelected, "nonsense changes nothing")
        XCTAssertEqual(hex.value as? String, "#D1E0F0")
    }

    // Custom opens the shared custom color sheet (screens 14 and 20) on the
    // page's color: a typed HEX previews on the page, Apply keeps it as one
    // undo step, and a tap outside drops a change.
    func testCustomSheetHexSetsThePageColor() {
        startMemory()
        openTool()
        app.buttons["background.color.custom"].tap()
        let hex = app.textFields["background.colorSheet.hex"]
        let apply = app.buttons["background.colorSheet.apply"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5), "the custom color sheet is up")
        XCTAssertEqual(hex.value as? String, "#F6F4E8", "a default page starts the sheet on paper")
        replace(hex, with: "8B5962")
        hex.typeText("\n")
        XCTAssertEqual(previewColor, "PREVIEW COLOR  \u{00B7}  #8B5962", "the page previews the typed color")
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5), "Apply closes the sheet")
        XCTAssertEqual(previewColor, "PREVIEW COLOR  \u{00B7}  #8B5962", "and keeps the color")
        app.buttons["Undo"].tap()
        XCTAssertEqual(previewColor, "PREVIEW COLOR  \u{00B7}  DEFAULT", "one undo step takes it off")

        app.buttons["background.color.custom"].tap()
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        replace(hex, with: "112233")
        hex.typeText("\n")
        XCTAssertEqual(previewColor, "PREVIEW COLOR  \u{00B7}  #112233")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5), "a tap outside closes the sheet")
        XCTAssertEqual(previewColor, "PREVIEW COLOR  \u{00B7}  DEFAULT", "and drops the change")
    }

    // Pick goes straight to the eyedropper over the page; its Cancel leaves
    // the sheet up on the page's color.
    func testPickOpensTheEyedropper() {
        startMemory()
        openTool()
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

    // A painted backdrop is nobody's swatch; any dot replaces it.
    func testASwatchReplacesAPaintedBackdrop() {
        startMemory()
        ask("give this page a sunset background")
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 5))
        app.buttons["mira.keep"].tap()

        openTool()
        XCTAssertEqual(previewColor, "PREVIEW COLOR  \u{00B7}  PAINTED")
        let paper = app.buttons["background.color.#F6F4E8"]
        XCTAssertFalse(paper.isSelected, "a painted page wears no swatch")
        paper.tap()
        XCTAssertTrue(paper.isSelected, "the dot replaced the painting")
        XCTAssertEqual(previewColor, "PREVIEW COLOR  \u{00B7}  #F6F4E8")
    }
}
