import XCTest

/// An AI edit that fails says why, in the app's own words, wherever it was
/// asked for: Photo Editing's "change with words", Edit sticker, and Mira.
/// `-AI_EDIT_FAIL <status>:<reason>` has /stylize answer as miranote-api
/// #103 does, read by the live client.
final class ImageEditErrorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func launch(failing failure: String) {
        app.launchArguments = ["-UITEST", "-AI_EDIT_FAIL", failure]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
    }

    /// Draw-and-place one sticker, then Keep it, so the strip is quiet.
    private func placeOneSticker() {
        app.askMira("draw a sticker of a coffee cup")
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        let keep = app.buttons["mira.keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        keep.tap()
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["mira.receipt"])
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "Keep clears the result sheet")
    }

    func testAPhotoEditMiraWillNotMakeSaysSo() {
        launch(failing: "422:edit_refused")
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        let photo = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["Edit photo"].waitForExistence(timeout: 5))
        app.buttons["Edit photo"].tap()
        app.buttons["photo.tile.ai"].tap()
        let field = app.textFields["photo.prompt"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("make it autumn")
        app.buttons["photo.composer.action"].tap()

        let notice = app.staticTexts["photo.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 8), "the edit's failure is shown")
        XCTAssertEqual(notice.label, "Mira won't make that edit. Try describing it differently.")
    }

    func testAStickerEditWhileMiraIsBusySaysSo() {
        launch(failing: "503:busy")
        placeOneSticker()
        let sticker = app.descendants(matching: .any).matching(identifier: "element.sticker").firstMatch
        sticker.press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Edit sticker"].waitForExistence(timeout: 5))
        app.buttons["Edit sticker"].tap()
        let field = app.textFields["sticker.ai.instruction"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("make it blue")
        app.buttons["sticker.ai.run"].tap()

        XCTAssertTrue(
            app.staticTexts["Mira is busy right now. Wait a moment and try again."].waitForExistence(timeout: 8),
            "the panel says why the edit failed"
        )
    }

    /// Mira's own card says the same, not "That one did not go through".
    func testMiraSaysWhyAStickerEditFailed() {
        launch(failing: "503:busy")
        placeOneSticker()
        app.askMira("make the sticker blue")

        let failure = app.staticTexts["mira.failure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 8))
        XCTAssertEqual(failure.label, "Mira is busy right now. Wait a moment and try again.")
    }
}
