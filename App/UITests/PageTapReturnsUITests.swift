import XCTest

/// A tap on the page folds an open-but-idle tool back to the plain canvas:
/// the Image and Sticker panels return to the canvas, an armed (not yet
/// recording) Voice bar folds away. The page carries no accessibility
/// identifier on purpose (a container id cascades onto its elements), so
/// taps go by coordinate.
final class PageTapReturnsUITests: XCTestCase {
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
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5))
    }

    private func tapPage() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    }

    private func waitGone(_ element: XCUIElement, _ message: String) {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, message)
    }

    func testTapOnPageLeavesImagePanel() {
        startMemory()
        app.buttons["mode.image"].tap()
        let library = app.buttons["image.library.open"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))

        // The side margins are not the page: a tap there stays put.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.25)).tap()
        sleep(1)
        XCTAssertTrue(library.exists, "a margin tap keeps the panel open")

        tapPage()
        waitGone(library, "a page tap closes the Image panel")
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5),
                      "back on the idle canvas")
    }

    func testTapOnPageKeepsPhotosBeingPicked() {
        startMemory()
        app.buttons["mode.image"].tap()
        app.buttons["image.library.open"].tap()
        let first = app.descendants(matching: .any).matching(identifier: "image.library.photo.0").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertTrue(first.isSelected)

        tapPage()
        sleep(1)
        XCTAssertTrue(first.exists, "a pick in progress is not dropped by a page tap")
        XCTAssertTrue(first.isSelected)
    }

    // Saved became the Sticker tool (Favorites live there).
    func testTapOnPageLeavesStickerPanel() {
        startMemory()
        app.buttons["mode.sticker"].tap()
        let favorites = app.buttons["Favorites"].exists
            ? app.buttons["Favorites"] : app.staticTexts["Favorites"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))

        // Scrolling the preview is not a tap.
        let page = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        page.press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        sleep(1)
        XCTAssertTrue(favorites.exists, "a swipe on the page keeps the panel open")

        // The side margins are not the page either.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.25)).tap()
        sleep(1)
        XCTAssertTrue(favorites.exists, "a margin tap keeps the panel open")

        tapPage()
        waitGone(favorites, "a page tap closes the Sticker panel")
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5),
                      "back on the idle canvas")
    }

    func testTapOnPageKeepsUnpickedStickers() {
        startMemory()
        app.buttons["mode.sticker"].tap()
        let prompt = app.textFields["sticker.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("a coffee cup")
        app.buttons["sticker.generate.run"].tap()
        let firstResult = app.descendants(matching: .any).matching(identifier: "sticker.result.0").firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 8))

        tapPage()
        sleep(1)
        XCTAssertTrue(firstResult.exists, "unpicked stickers are not dropped by a page tap")
    }

    func testTapOnPaperFoldsArmedSoundButNotRecording() {
        startMemory()
        app.buttons["mode.voice"].tap()
        let record = app.buttons["recorder.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))

        tapPage()
        waitGone(record, "a paper tap folds the armed recorder")
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5),
                      "back on the idle canvas")

        // Once recording, the bar stays: a stray tap must not lose audio.
        app.buttons["mode.voice"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        let stop = app.buttons["recorder.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        tapPage()
        sleep(1)
        XCTAssertTrue(stop.exists, "recording keeps its bar")
    }
}
