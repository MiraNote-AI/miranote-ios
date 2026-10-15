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
    // to paint a backdrop -- candidates and all -- and the sheet steps
    // aside for the turn.
    func testApplyToThisPageAsksMiraForABackdrop() {
        startMemory()
        openTool()
        let words = app.textFields["background.apply.input"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["background.apply"].isEnabled, "nothing to apply yet")
        words.tap()
        words.typeText("a soft sunset glow")
        app.buttons["background.apply"].tap()

        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "the words came back as background candidates")
        XCTAssertFalse(app.staticTexts["background.title"].exists, "the sheet steps aside for the turn")
        first.tap()
        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 5))
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
