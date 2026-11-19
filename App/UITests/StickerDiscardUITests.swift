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

    /// The sticker panel's made stickers, from the debug probe.
    private var draftCount: Int? {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"sticker\"'")).firstMatch
        guard probe.waitForExistence(timeout: 5) else { return nil }
        let state = (try? JSONSerialization.jsonObject(with: Data(probe.label.utf8))) as? [String: Any]
        return state?["drafts"] as? Int
    }

    /// Two made, the second showing: Discard drops it and the first shows,
    /// still live (Discard and Add work on it); the last one gone is Make's
    /// start.
    func testDiscardLetsGoOfTheShowingStickerOnly() {
        let prompt = app.textFields["sticker.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("a coffee cup")
        app.buttons["sticker.generate.run"].tap()
        let first = any("sticker.result.0")
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertEqual(draftCount, 2, "the studio made two")

        let discard = app.buttons["sticker.draft.discard"]
        let redo = app.buttons["sticker.redo"]
        XCTAssertTrue(discard.isEnabled)
        XCTAssertEqual(discard.frame.midY, redo.frame.midY, accuracy: 1, "in the undo / redo row")
        // Frames carry the circles' 5 pt hit slop: 19 apart here, 0 without the hairline.
        XCTAssertGreaterThan(discard.frame.minX, redo.frame.maxX + 15, "past redo and the hairline")

        first.swipeLeft()
        XCTAssertTrue(any("sticker.result.1").waitForExistence(timeout: 3), "the second one shows")
        discard.tap()
        sleep(1)
        XCTAssertEqual(draftCount, 1, "only the showing one went")
        XCTAssertTrue(first.exists, "the other one shows")
        XCTAssertTrue(discard.isEnabled, "the one left is live")
        XCTAssertTrue(app.buttons["sticker.addToPage"].isEnabled)

        discard.tap()
        XCTAssertTrue(first.waitForNonExistence(timeout: 3))
        XCTAssertEqual(draftCount, 0)
        XCTAssertFalse(discard.exists, "Make is back at its start")
        XCTAssertTrue(app.staticTexts["Describe a sticker below -- Mira makes a couple to pick from."].exists)
        XCTAssertEqual(app.buttons["nav.trailing"].label, "Add", "nothing waits: the header Add is back")
        XCTAssertFalse(any("element.sticker").exists, "nothing landed on the page")
    }
}
