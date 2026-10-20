import XCTest

/// A raised keyboard comes down without sending, and the words stay (#120).
/// On Home a tap on the page or a scroll lowers it; in the editor a tap on
/// the tool's sheet (the photo, Mira's panel) lowers it and the panel stays
/// open. Where leaving would drop the words, the first tap on the page only
/// lowers the keyboard.
final class KeyboardDismissUITests: XCTestCase {
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

    private var keyboard: XCUIElement { app.keyboards.firstMatch }

    private func type(_ words: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the field is there", file: file, line: line)
        field.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4), "the keyboard comes up", file: file, line: line)
        field.typeText(words)
    }

    private func raiseKeyboard(_ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        field.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4), "the keyboard comes back up", file: file, line: line)
    }

    private func waitUntilGone(_ element: XCUIElement, _ message: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, message, file: file, line: line)
    }

    private func assertKeyboardStays(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: keyboard)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 1.5), .timedOut, message, file: file, line: line)
    }

    /// A point on the screen, in points from its top-left corner.
    private func point(_ left: CGFloat, _ top: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: left, dy: top))
    }

    private func startMemory() {
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    // MARK: Home

    func testATapOnHomeLowersTheAskBarsKeyboardAndKeepsTheWords() {
        let field = app.textFields["quick.field"]
        type("Paris", into: field)
        field.tap()
        assertKeyboardStays("a tap in the field keeps the keyboard")
        // The star circle, outside the field but on the bar.
        point(field.frame.minX - 25, field.frame.midY).tap()
        assertKeyboardStays("a tap anywhere on the bar keeps the keyboard")

        app.staticTexts["Your memory,"].tap()
        waitUntilGone(keyboard, "a tap on the page lowers the keyboard")
        XCTAssertEqual(field.value as? String, "Paris", "the words stay in the bar")
        XCTAssertTrue(app.buttons["Start a memory"].exists, "nothing was sent: Home is still up")
    }

    func testAScrollOnHomeLowersTheKeyboardAndKeepsTheWords() {
        let field = app.textFields["quick.field"]
        type("Paris", into: field)
        let hero = app.staticTexts["Your memory,"]
        hero.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: hero.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -3)))
        waitUntilGone(keyboard, "a scroll lowers the keyboard")
        XCTAssertEqual(field.value as? String, "Paris", "the words stay in the bar")
    }

    /// The bar's own tap (it focuses the field) leaves the field its taps: a
    /// tap before the words still puts the caret there.
    func testATapInTheAskBarStillMovesTheCaret() {
        let field = app.textFields["quick.field"]
        // Two words: a tap on the word the caret is in shows the edit menu
        // instead of moving the caret, so the tap goes to the first word.
        type("Paris trip", into: field)
        // Two points into the field: before the P.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 2, dy: 0)).tap()
        field.typeText("X")
        XCTAssertEqual(field.value as? String, "XParis trip", "the tap put the caret before the words")
    }

    // MARK: Editor

    /// Mira's panel lowers the keyboard and the chat stays; the dimmed page
    /// still closes the chat at once, the question kept in the composer.
    func testTheMiraQuestionLowersOnItsPanel() {
        startMemory()
        app.openMiraChat()
        type("a picnic", into: app.miraInput)
        app.staticTexts["Mira can edit this canvas directly."].tap()
        waitUntilGone(keyboard, "a tap on Mira's panel lowers the keyboard")
        XCTAssertTrue(app.miraInput.exists, "the chat stays open")
        XCTAssertEqual(app.miraInput.value as? String, "a picnic", "the question stays")

        raiseKeyboard(app.miraInput)
        let frame = app.miraInput.frame
        point(frame.minX / 2, frame.midY).tap()
        waitUntilGone(app.miraInput, "a tap on the dimmed page closes the chat")
        XCTAssertEqual(app.miraComposer.label, "a picnic", "the draft waits in the composer")
    }

    func testATapOnTheBackgroundSheetLowersTheApplyKeyboard() {
        startMemory()
        app.buttons["mode.background"].tap()
        let field = app.textFields["background.apply.input"]
        type("a sunset", into: field)
        app.staticTexts["background.title"].tap()
        waitUntilGone(keyboard, "a tap on the Background sheet lowers the keyboard")
        XCTAssertEqual(field.value as? String, "a sunset", "the words stay")
        XCTAssertTrue(app.staticTexts["background.title"].exists, "the sheet stays open")
    }

    /// The Sticker sheet lowers the keyboard; the page does too while it is
    /// up (closing would drop the words), and goes back once it is down.
    func testTheStickerPromptLowersOnItsSheetAndOnTheFirstTapOnThePage() {
        startMemory()
        app.buttons["mode.sticker"].tap()
        let field = app.textFields["sticker.prompt"]
        type("a cat", into: field)
        app.staticTexts["Sticker"].tap()
        waitUntilGone(keyboard, "a tap on the Sticker sheet lowers the keyboard")
        XCTAssertEqual(field.value as? String, "a cat", "the words stay")

        raiseKeyboard(field)
        let page = point(app.frame.midX, app.buttons["Cancel"].frame.maxY + 40)
        page.tap()
        waitUntilGone(keyboard, "the first tap on the page lowers the keyboard")
        XCTAssertTrue(field.exists, "the panel stays open")
        XCTAssertEqual(field.value as? String, "a cat", "the words stay")
        page.tap()
        waitUntilGone(field, "with the keyboard down, a tap on the page goes back to the canvas")
    }

    /// With nothing typed there is nothing to keep: the first tap on the page
    /// goes back to the canvas.
    func testAnEmptyStickerPromptLeavesOnTheFirstTapOnThePage() {
        startMemory()
        app.buttons["mode.sticker"].tap()
        let field = app.textFields["sticker.prompt"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        raiseKeyboard(field)
        point(app.frame.midX, app.buttons["Cancel"].frame.maxY + 40).tap()
        waitUntilGone(field, "with nothing typed, the first tap on the page goes back to the canvas")
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "back on the idle canvas")
    }

    /// While a made sticker waits to be added, a tap on the page stays (leaving
    /// would drop the sticker) but still lowers the keyboard, words or not.
    func testATapOnThePageLowersTheKeyboardWhileAStickerWaits() {
        startMemory()
        app.buttons["mode.sticker"].tap()
        let field = app.textFields["sticker.prompt"]
        type("a cat", into: field)
        app.buttons["sticker.generate.run"].tap()
        let made = app.descendants(matching: .any).matching(identifier: "sticker.result.0").firstMatch
        XCTAssertTrue(made.waitForExistence(timeout: 8))
        // Empty the prompt; the sticker still waits.
        raiseKeyboard(field)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        XCTAssertFalse(app.buttons["sticker.generate.run"].isEnabled, "the prompt is empty")
        point(app.frame.midX, app.buttons["Cancel"].frame.maxY + 40).tap()
        waitUntilGone(keyboard, "a tap on the page lowers the keyboard")
        XCTAssertTrue(made.waitForExistence(timeout: 5), "the sticker waiting to be added stays")
    }

    /// The Photo Editing sheet sits under the keyboard: the photo lowers it,
    /// and so does the first tap on the page beside a tall photo (closing
    /// would drop the words); once it is down, that tap closes the editor.
    func testThePhotoPromptLowersOnThePhotoAndOnTheFirstTapBesideIt() {
        openPhotoEditor(photoAt: 1)
        app.buttons["photo.tile.ai"].tap()
        let field = app.textFields["photo.prompt"]
        type("make it warm", into: field)
        let photo = app.descendants(matching: .any)["photo.lifted"]
        photo.tap()
        waitUntilGone(keyboard, "a tap on the photo lowers the keyboard")
        XCTAssertEqual(field.value as? String, "make it warm", "the words stay")
        XCTAssertTrue(app.buttons["photo.tile.ai"].isHittable, "the photo editor stays open, its sheet back in view")

        raiseKeyboard(field)
        XCTAssertGreaterThan(photo.frame.minX, 60, "Sample two is tall: the page shows beside it")
        let beside = point(photo.frame.minX / 2 + 10, photo.frame.minY + 60)
        beside.tap()
        waitUntilGone(keyboard, "the first tap beside the photo lowers the keyboard")
        XCTAssertTrue(field.exists, "the photo editor stays open")
        XCTAssertEqual(field.value as? String, "make it warm", "the words stay")
        beside.tap()
        waitUntilGone(field, "with the keyboard down, a tap beside the photo closes the editor")
    }

    /// With nothing typed the first tap beside the photo closes the editor.
    func testAnEmptyPhotoPromptClosesOnTheFirstTapBesideThePhoto() {
        openPhotoEditor(photoAt: 1)
        app.buttons["photo.tile.ai"].tap()
        let field = app.textFields["photo.prompt"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        raiseKeyboard(field)
        let photo = app.descendants(matching: .any)["photo.lifted"]
        XCTAssertGreaterThan(photo.frame.minX, 60, "Sample two is tall: the page shows beside it")
        point(photo.frame.minX / 2 + 10, photo.frame.minY + 60).tap()
        waitUntilGone(field, "with nothing typed, the first tap beside the photo closes the editor")
        waitUntilGone(app.buttons["photo.tile.ai"], "the photo editor is closed, not only its prompt")
    }

    /// Edit sticker sits on the shared tool chrome: a tap on the paper
    /// lowers its keyboard and the editor stays.
    func testATapOnThePaperLowersTheEditStickerKeyboard() {
        startMemory()
        placeOneSticker()
        app.descendants(matching: .any).matching(identifier: "element.sticker").firstMatch.press(forDuration: 1.1)
        let entry = app.buttons["Edit sticker"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let field = app.textFields["sticker.ai.instruction"]
        type("make it blue", into: field)
        // The field's capsule, by its trailing end: 8 before Go, then 4 in.
        point(app.buttons["sticker.ai.run"].frame.minX - 12, field.frame.midY).tap()
        assertKeyboardStays("a tap on the field's capsule keeps the keyboard")
        // The capsule's tap leaves the field its own. The field's frame takes
        // in the capsule's 12 pt padding: 14 in is just before the m.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 14, dy: 0)).tap()
        field.typeText("X")
        XCTAssertEqual(field.value as? String, "Xmake it blue", "a tap in the field still moves the caret")
        let board = app.scrollViews.containing(.any, identifier: "element.sticker").firstMatch
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)).tap()
        waitUntilGone(keyboard, "a tap on the paper lowers the keyboard")
        XCTAssertEqual(field.value as? String, "Xmake it blue", "the words stay")
        XCTAssertTrue(field.exists, "Edit sticker stays open")
    }

    // MARK: Setup

    /// Samples land two photos (Sample two is twice as tall as wide); the
    /// one at `index` opens in the photo editor.
    private func openPhotoEditor(photoAt index: Int) {
        startMemory()
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        let photo = app.descendants(matching: .any).matching(identifier: "element.image").element(boundBy: index)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        // As in PhotoRevertUITests: let go of the selection in the margin and
        // drag the page back until the photo is in reach.
        let board = app.scrollViews.containing(.image, identifier: "element.image").firstMatch
        let margin = board.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.3))
        if !photo.isHittable { margin.tap() }
        for _ in 0..<3 where !photo.isHittable {
            margin.press(forDuration: 0.05,
                         thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.9)))
        }
        photo.press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["Edit photo"].waitForExistence(timeout: 5))
        app.buttons["Edit photo"].tap()
        XCTAssertTrue(app.buttons["photo.tile.ai"].waitForExistence(timeout: 5))
    }

    /// As in StickerEditUITests: Mira draws one, it is placed and kept.
    private func placeOneSticker() {
        app.askMira("draw a sticker of a coffee cup")
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        let keep = app.buttons["mira.keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        keep.tap()
        waitUntilGone(app.staticTexts["mira.receipt"], "Keep clears the result sheet")
    }
}
