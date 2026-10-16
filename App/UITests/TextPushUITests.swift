import XCTest

/// What a text block's growth pushes is the block's to take back, and only
/// that: Cancel never moves what Mira moved meanwhile, and the curated sets
/// toggled back and forth leave the page where it was.
final class TextPushUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private var field: XCUIElement { app.descendants(matching: .any)["canvas.textEditor"] }

    /// A title lands while the user writes and slides the page down; Cancel
    /// keeps the block under the title.
    func testCancelAfterATitleLandedKeepsTheBlockUnderIt() {
        app.launchArguments = ["-UITEST", "-CHAT_DELAY", "6000"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lunch by the river")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["keyboard.done"].waitForNonExistence(timeout: 5))

        app.openMiraChat()
        app.buttons["mira.action.Add soft title"].tap()
        XCTAssertTrue(app.miraInput.waitForNonExistence(timeout: 5), "the chat steps aside for the turn")
        let block = app.staticTexts["lunch by the river"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        block.tap()
        if !field.waitForExistence(timeout: 2) { block.tap() }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "writing opens while Mira works")
        field.typeText(" and a walk")
        let title = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'scripted'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the title lands")
        sleep(1)

        app.buttons["text.cancel"].tap()
        XCTAssertTrue(block.waitForExistence(timeout: 5), "the block's words are back")
        XCTAssertGreaterThanOrEqual(block.frame.minY, title.frame.maxY - 1,
                                    "Cancel put the block back on the title")
    }

    /// "A little welcome": Poppins / Lora and Didot / Cardo tapped in turn,
    /// three rounds -- the sticker below the words sits where the first
    /// round put it under each set.
    func testCuratedSetsBackAndForthLeaveTheStickerPut() {
        app.launchArguments = ["-UITEST"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        let joys = app.buttons["collection.Little Joys"]
        for _ in 0..<4 where !joys.isHittable { app.swipeUp() }
        joys.tap()
        let cover = app.buttons["note.A little welcome"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        cover.tap()
        XCTAssertTrue(app.buttons["reading.edit"].waitForExistence(timeout: 5))
        app.buttons["reading.edit"].tap()
        XCTAssertTrue(app.buttons["mode.background"].waitForExistence(timeout: 5))
        app.buttons["mode.background"].tap()

        let sticker = app.descendants(matching: .any)["element.sticker"].firstMatch
        let poppins = app.buttons["background.set.poppins-lora"]
        let didot = app.buttons["background.set.didot-cardo"]
        XCTAssertTrue(poppins.waitForExistence(timeout: 5))
        var underPoppins: [CGFloat] = []
        var underDidot: [CGFloat] = []
        for _ in 0..<3 {
            poppins.tap()
            sleep(1)
            underPoppins.append(sticker.frame.minY)
            didot.tap()
            sleep(1)
            underDidot.append(sticker.frame.minY)
        }
        for round in 1..<3 {
            XCTAssertEqual(underPoppins[round], underPoppins[0], accuracy: 0.5, "Poppins, round \(round + 1)")
            XCTAssertEqual(underDidot[round], underDidot[0], accuracy: 0.5, "Didot, round \(round + 1)")
        }
    }
}
