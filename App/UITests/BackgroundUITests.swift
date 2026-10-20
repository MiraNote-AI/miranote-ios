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

    private var probe: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
    }

    private func probeShows(_ fragment: String, timeout: TimeInterval = 5) -> Bool {
        let shows = NSPredicate(format: "label CONTAINS %@", fragment)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shows, object: probe)],
                                timeout: timeout) == .completed
    }

    /// The canvas is back: the sheet is gone and the Mira composer shows.
    private func assertBackOnTheCanvas(_ message: String) {
        XCTAssertTrue(app.staticTexts["background.title"].waitForNonExistence(timeout: 5), message)
        XCTAssertTrue(app.buttons["mira.go"].waitForExistence(timeout: 5), "the canvas composer is back")
        XCTAssertFalse(app.buttons["mode.background"].isSelected, "the tool is closed")
    }

    // Owner, TestFlight 1.0(6): Apply with nothing typed was a dead button.
    // It closes the sheet and keeps everything the sheet applied.
    func testApplyWithNoWordsReturnsToTheCanvasKeepingThePicks() {
        startMemory()
        openTool()
        app.buttons["background.paper.grid"].tap()
        app.buttons["background.color.#E6D9F0"].tap()
        let apply = app.buttons["background.apply"]
        XCTAssertTrue(apply.isEnabled, "Apply is never dead while the sheet is open")
        apply.tap()

        assertBackOnTheCanvas("Apply closed the sheet")
        XCTAssertTrue(probeShows("\"pageColor\":\"#E6D9F0\""), "the color stays: \(probe.label)")
        XCTAssertTrue(probeShows("\"paper\":\"grid\""), "the paper stays: \(probe.label)")
    }

    // A hex typed but not yet confirmed is still the user's pick.
    func testApplyKeepsATypedHex() {
        startMemory()
        openTool()
        let hex = app.textFields["background.hex"]
        hex.tap()
        hex.typeText("d1e0f0")
        app.buttons["background.apply"].tap()
        assertBackOnTheCanvas("Apply closed the sheet")
        XCTAssertTrue(probeShows("\"pageColor\":\"#D1E0F0\""), "the typed hex applied: \(probe.label)")
    }

    // The tool's composer is "Apply to this page": the typed words ask Mira
    // to paint a backdrop, the sheet shows the work, and when the painting
    // lands it is on the page and the canvas is back with its result sheet.
    // Owner, TestFlight 1.0(5): Apply did nothing visible -- the painting
    // waited as thumbnails for a second pick. With the painting taking its
    // time, as the live backend does.
    func testApplyToThisPagePaintsThePage() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-GENERATE_DELAY", "3000"]
        app.launch()
        startMemory()
        openTool()
        let words = app.textFields["background.apply.input"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap()
        words.typeText("a soft sunset glow")
        app.buttons["background.apply"].tap()

        let status = app.staticTexts["background.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3), "the sheet shows the work")
        XCTAssertTrue(app.staticTexts["background.title"].exists, "the sheet stays up while painting")
        XCTAssertEqual(app.buttons["background.apply"].label, "Stop", "the work can be stopped")

        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 12),
                      "Apply's painting landed")
        assertBackOnTheCanvas("the sheet closed once the painting landed")
        XCTAssertFalse(app.buttons["mira.imageChoice.0"].exists, "no second pick")
        XCTAssertTrue(probeShows("\"backdropDescribes\":\"a soft sunset glow\""),
                      "the page wears the new painting: \(probe.label)")
        XCTAssertTrue(app.buttons["mira.revert"].exists, "Revert / Keep on the canvas")
    }

    // While Apply paints, the page color controls rest: a color picked or a
    // hex typed then would wipe the paid painting when it lands (#127
    // review). The painting lands on the page all the same.
    func testColorControlsRestWhileApplyPaints() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-GENERATE_DELAY", "4000"]
        app.launch()
        startMemory()
        openTool()
        let words = app.textFields["background.apply.input"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap()
        words.typeText("a soft sunset glow")
        app.buttons["background.apply"].tap()
        XCTAssertTrue(app.staticTexts["background.status"].waitForExistence(timeout: 3))

        for id in ["background.color.custom", "background.color.pick",
                   "background.color.#E6D9F0", "background.layout"] {
            XCTAssertFalse(app.buttons[id].isEnabled, "\(id) rests while painting")
        }
        XCTAssertFalse(app.textFields["background.hex"].isEnabled, "the hex field rests while painting")
        app.buttons["background.color.custom"].tap()
        XCTAssertFalse(app.buttons["Cancel"].waitForExistence(timeout: 1), "no color sheet opens")

        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 12))
        XCTAssertTrue(probeShows("\"backdropDescribes\":\"a soft sunset glow\""),
                      "the painting stays on the page: \(probe.label)")
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
        app.staticTexts["background.title"].tap()
        app.buttons["background.apply"].doubleTap()
        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 12),
                      "the painting landed")
    }

    // The color dots tap as 44 x 44 boxes.
    func testColorDotsHaveFullTapTargets() {
        startMemory()
        openTool()
        for id in ["background.color.#E6D9F0", "background.color.custom", "background.color.pick"] {
            let dot = app.buttons[id]
            XCTAssertTrue(dot.waitForExistence(timeout: 5))
            XCTAssertEqual(dot.frame.width, 44, accuracy: 0.5, id)
            XCTAssertEqual(dot.frame.height, 44, accuracy: 0.5, id)
        }
    }

    // Stop gives the words back, the sheet stays and nothing is painted.
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

        XCTAssertEqual(words.value as? String, "a soft sunset glow", "the words are back")
        XCTAssertTrue(app.staticTexts["background.title"].exists, "the sheet stays")
        sleep(5)
        XCTAssertFalse(app.staticTexts["Set the page background."].exists, "nothing landed")
        XCTAssertTrue(probeShows("\"backdrop\":\"\""), "the page is untouched: \(probe.label)")
    }

    // A painting that does not come stays in the sheet and says so, with
    // the words back for another try; the page is untouched.
    func testApplyFailureStaysInTheSheetWithANotice() {
        startMemory()
        openTool()
        let words = app.textFields["background.apply.input"]
        words.tap()
        words.typeText("fail this one")
        app.buttons["background.apply"].tap()

        let notice = app.staticTexts["background.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 8), "the failure is said in the sheet")
        XCTAssertTrue(app.staticTexts["background.title"].exists, "the sheet stays")
        XCTAssertEqual(words.value as? String, "fail this one", "the words are back")
        XCTAssertTrue(probeShows("\"backdrop\":\"\""), "the page is untouched: \(probe.label)")
        // The strip's failure shows only on the bare canvas: leave the tool
        // so this check could fail.
        app.buttons["Canvas"].tap()
        assertBackOnTheCanvas("Canvas closed the tool")
        XCTAssertFalse(app.staticTexts["mira.failure"].waitForExistence(timeout: 2), "said once, in the sheet")
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
