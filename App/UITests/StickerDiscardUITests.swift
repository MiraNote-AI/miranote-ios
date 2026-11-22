import XCTest

/// #205 (J1C, J3A): Discard beside the made sticker's undo and redo lets go
/// of the one on screen only; the next shows, and the last one gone leaves
/// Make as it starts. Not undoable.
final class StickerDiscardUITests: XCTestCase {
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

    /// The sticker panel's debug probe.
    private var panelState: [String: Any]? {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"sticker\"'")).firstMatch
        guard probe.waitForExistence(timeout: 5) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(probe.label.utf8))) as? [String: Any]
    }

    /// The sticker panel's made stickers, from the debug probe.
    private var draftCount: Int? { panelState?["drafts"] as? Int }

    /// The fake studio makes two, alike; the first shows.
    private func makeTwo() {
        let prompt = app.textFields["sticker.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("a coffee cup")
        app.buttons["sticker.generate.run"].tap()
        XCTAssertTrue(any("sticker.result.0").waitForExistence(timeout: 8))
        XCTAssertEqual(draftCount, 2, "the studio made two")
    }

    private func waitUntil(_ element: XCUIElement, isSelected selected: Bool, _ message: String) {
        let lit = NSPredicate(format: "isSelected == %@", NSNumber(value: selected))
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: lit, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, message)
    }

    /// Two made, the second showing: Discard drops it and the first shows,
    /// still live (Discard and Add work on it); the last one gone is Make's
    /// start.
    func testDiscardLetsGoOfTheShowingStickerOnly() {
        makeTwo()
        let first = any("sticker.result.0")
        let discard = app.buttons["sticker.draft.discard"]
        let redo = app.buttons["sticker.redo"]
        XCTAssertTrue(discard.isEnabled)
        XCTAssertEqual(discard.frame.midY, redo.frame.midY, accuracy: 1, "in the undo / redo row")
        // Frames carry the circles' 5 pt hit slop: 19 apart here, 0 without the hairline.
        XCTAssertGreaterThan(discard.frame.minX, redo.frame.maxX + 15, "past redo and the hairline")

        // The two come out alike: the first one cut out, so it can be told
        // from the second by its lit style tile.
        let cutout = app.buttons["sticker.style.cutout"]
        cutout.tap()
        waitUntil(cutout, isSelected: true, "the first one is cut out")
        first.swipeLeft()
        XCTAssertTrue(any("sticker.result.1").waitForExistence(timeout: 3), "the second one shows")
        waitUntil(cutout, isSelected: false, "the second one is as it came")
        discard.tap()
        sleep(1)
        XCTAssertEqual(draftCount, 1, "only the showing one went")
        XCTAssertTrue(first.exists, "the other one shows")
        XCTAssertTrue(cutout.isSelected, "the one left is the cut-out first one, not the second")
        XCTAssertTrue(discard.isEnabled, "the one left is live")
        XCTAssertTrue(app.buttons["sticker.addToPage"].isEnabled)

        discard.tap()
        XCTAssertTrue(first.waitForNonExistence(timeout: 3))
        XCTAssertEqual(draftCount, 0)
        XCTAssertFalse(discard.exists, "Make is back at its start")
        XCTAssertTrue(app.staticTexts["Describe a sticker below -- Mira makes a couple to pick from."].exists)
        XCTAssertEqual(app.buttons["nav.leading"].label, "Home", "nothing waits: Cancel gives way to Home")
        XCTAssertFalse(app.buttons["nav.leading"].isEnabled, "greyed while the panel is open (#229)")
        XCTAssertFalse(any("element.sticker").exists, "nothing landed on the page")
    }

    /// #236: VoiceOver hears that the sticker went -- from two to one, focus
    /// stays on Discard and only the page dots change.
    func testDiscardIsAnnounced() {
        makeTwo()
        app.buttons["sticker.draft.discard"].tap()
        sleep(1)
        XCTAssertEqual(draftCount, 1)
        XCTAssertEqual(panelState?["announced"] as? String, "Discarded the sticker")
    }

    /// In Chinese, with the catalog's word for Discard.
    func testDiscardIsAnnouncedInChinese() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.sticker"].waitForExistence(timeout: 5))
        app.buttons["mode.sticker"].tap()
        makeTwo()
        app.buttons["sticker.draft.discard"].tap()
        sleep(1)
        XCTAssertEqual(draftCount, 1)
        // "Discarded this sticker", as Unicode escapes: Swift source stays
        // ASCII (org rule 3).
        XCTAssertEqual(panelState?["announced"] as? String,
                       "\u{5DF2}\u{653E}\u{5F03}\u{8FD9}\u{5F20}\u{8D34}\u{7EB8}")
    }

    /// Discard stays put after it lets one go, and the one left often looks
    /// the same: a double tap lets go of one, not both. Neither comes back.
    func testADoubleTapOnDiscardLetsGoOfOneOnly() {
        makeTwo()
        let discard = app.buttons["sticker.draft.discard"]
        discard.doubleTap()
        sleep(1)
        XCTAssertEqual(draftCount, 1, "one double tap, one sticker gone")
        XCTAssertTrue(discard.isEnabled, "the one left is live")
    }
}
