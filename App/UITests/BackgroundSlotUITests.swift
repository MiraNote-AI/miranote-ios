import XCTest

/// The Background tool in the tool slot (#205, REQ 11-18 overlay rule):
/// one row at a time, the card's size kept, deterministic under -UITEST.
final class BackgroundSlotUITests: XCTestCase {
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

    /// Exactly one row in the slot, and no tool bar beside it.
    private func assertOneRow(_ id: String, _ message: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let row = app.descendants(matching: .any)[id]
        XCTAssertTrue(row.waitForExistence(timeout: 5), message, file: file, line: line)
        // Mid level change the old row fades out over 0.22 s.
        let one = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"),
                                            object: app.backgroundSlotRows)
        XCTAssertEqual(XCTWaiter().wait(for: [one], timeout: 3), .completed,
                       "\(message): one row, not \(app.backgroundSlotRows.count)", file: file, line: line)
        XCTAssertFalse(app.buttons["mode.background"].exists, "\(message): the tool bar is gone",
                       file: file, line: line)
        let backs = app.buttons.matching(
            NSPredicate(format: "identifier IN {'background.back', 'background.row.back'}"))
        XCTAssertEqual(backs.count, 1, "\(message): one Back", file: file, line: line)
    }

    // REQ 11-18 overlay rule: Background replaces the tool bar with its
    // items, an item replaces them with its row, and Back goes up exactly
    // one level -- never two rows stacked. The header greys Home and Save
    // at every level (D5A, F1A).
    func testOnlyOneToolSlotRowExistsAtEachLevel() {
        startMemory()
        let home = app.buttons["Home"]
        let save = app.buttons["Save"]
        XCTAssertTrue(home.isEnabled)
        let mira = app.buttons["mira.go"]
        let toolBarFrame = app.buttons["mode.background"].frame

        app.openBackground()
        assertOneRow("background.row.tools", "the four items")
        sleep(1)
        XCTAssertTrue(app.buttons["background.tool.color"].showsInk, "the items rose in, not left faded out")
        XCTAssertFalse(mira.exists, "the composer reads Apply")
        for item in ["sets", "color", "paper", "tidy"] {
            XCTAssertTrue(app.buttons["background.tool.\(item)"].exists, item)
        }
        XCTAssertEqual(app.buttons["background.back"].frame.midY, toolBarFrame.midY, accuracy: 1,
                       "the row sits where the tool bar was")

        for row in ["sets", "color", "paper"] {
            app.openBackgroundRow(row)
            assertOneRow("background.row.\(row)", row)
            XCTAssertFalse(app.buttons["background.tool.sets"].exists, "\(row): the items are gone")
            XCTAssertEqual(app.buttons["background.row.back"].frame.midY, toolBarFrame.midY, accuracy: 1,
                           "\(row): Back stays on the tool bar's line")
            XCTAssertFalse(home.isEnabled, "\(row): Home greyed")
            XCTAssertFalse(save.isEnabled, "\(row): Save greyed")
            XCTAssertTrue(app.buttons["Undo"].exists, "\(row): Undo stays")
            app.backToBackgroundItems()
            assertOneRow("background.row.tools", "back from \(row)")
        }
        XCTAssertFalse(home.isEnabled, "Home greyed")
        XCTAssertFalse(save.isEnabled, "Save greyed")

        app.buttons["background.back"].tap()
        XCTAssertTrue(app.buttons["mode.background"].waitForExistence(timeout: 5), "Back went up to the tool bar")
        XCTAssertTrue(app.backgroundSlotRows.firstMatch.waitForNonExistence(timeout: 3), "no Background row left")
        sleep(1)
        XCTAssertTrue(app.buttons["mode.background"].showsInk, "the tool bar settled in, not left faded out")
        XCTAssertTrue(home.isEnabled, "Home is back")
        XCTAssertTrue(save.isEnabled, "Save is back")
    }

    // The sets tray (64) and paper tray (48) are taller than the slot and
    // stay centered on its line. The set cards rise over the card's foot,
    // which keeps its size, and take taps there. A tap on the blank page
    // goes back to the tool bar.
    func testTallerRowsRiseOverTheCardFootAndAPageTapCloses() {
        startMemory()
        let composer = app.buttons["mira.go"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        let toolBarTop = app.buttons["mode.background"].frame.minY
        let toolBarLine = app.buttons["mode.background"].frame.midY

        app.openBackgroundRow("sets")
        let didot = app.buttons["background.set.didot-cardo"]
        XCTAssertTrue(didot.waitForExistence(timeout: 5))
        XCTAssertLessThan(didot.frame.minY, toolBarTop, "the set cards rise over the card's foot")
        XCTAssertEqual(didot.frame.midY, toolBarLine, accuracy: 1, "centered on the tool bar's line")
        // Its top edge, above the slot, over the card's foot.
        didot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        XCTAssertTrue(didot.isSelected, "a card over the page takes the tap")

        app.openBackgroundRow("paper")
        let grid = app.buttons["background.paper.grid"]
        XCTAssertEqual(grid.frame.midY, toolBarLine, accuracy: 1, "centered on the tool bar's line")
        grid.tap()
        XCTAssertTrue(grid.isSelected)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        XCTAssertTrue(app.buttons["mode.background"].waitForExistence(timeout: 5), "a page tap closed the tool")
        XCTAssertTrue(app.backgroundSlotRows.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.buttons["mode.background"].frame.minY, toolBarTop, accuracy: 0.5,
                       "the tool bar is back on its line")
    }

    // Closed from an item's row, the tool opens again on its four items.
    func testReopeningStartsOnTheFourItems() {
        startMemory()
        app.openBackgroundRow("paper")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        XCTAssertTrue(app.buttons["mode.background"].waitForExistence(timeout: 5), "a page tap closed the tool")
        app.openBackground()
        XCTAssertFalse(app.descendants(matching: .any)["background.row.paper"].exists, "not on the paper row")
    }

    // With two elements Tidy is live: a tap leaves the tool for the tool
    // bar and Mira's turn, which ends on its result (G22).
    func testTidyClosesTheToolAndAsksMira() {
        startMemory()
        for words in ["lunch by the river", "the long way home"] {
            app.buttons["mode.text"].tap()
            let field = app.descendants(matching: .any)["canvas.textEditor"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText(words)
            app.buttons["keyboard.done"].tap()
            XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        }
        app.openBackground()
        let tidy = app.buttons["background.tool.tidy"]
        XCTAssertTrue(tidy.isEnabled, "two elements can be tidied")
        tidy.tap()
        XCTAssertTrue(app.buttons["mode.background"].waitForExistence(timeout: 5), "the tool bar is back")
        XCTAssertTrue(app.backgroundSlotRows.firstMatch.waitForNonExistence(timeout: 3))
        sleep(1)
        XCTAssertTrue(app.buttons["mode.text"].showsInk, "and drawn")
        // A change waits on its receipt; the UI-test Mira may answer in words.
        let ends = [app.staticTexts["mira.receipt"], app.staticTexts["mira.failure"], app.buttons["mira.dismissReply"]]
        let ended = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in ends.contains { $0.exists } }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [ended], timeout: 10), .completed, "Mira's tidy turn ran to its end")
    }
}
