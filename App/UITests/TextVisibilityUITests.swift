import XCTest

/// Owner, TestFlight 1.0(5): the text tools over the keyboard (the row,
/// the tool bar, the dictation strip) covered the block being written. A
/// block near the page bottom -- new, or opened again -- sits fully between
/// the header and the text tools while it is written.
final class TextVisibilityUITests: XCTestCase {
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

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private var field: XCUIElement { any("canvas.textEditor") }

    /// Three photos, so the next block lands near the page bottom.
    private func fillThePage() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        app.buttons["image.library.open"].tap()
        XCTAssertTrue(any("image.library.photo.0").waitForExistence(timeout: 5))
        for index in 0..<3 { any("image.library.photo.\(index)").tap() }
        app.buttons["image.composer.add"].tap()
        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    /// The block's frame lies below the header and above every text tool.
    private func assertClearOfTheTools(_ when: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["style.sizes"].waitForExistence(timeout: 5))
        // The scroll into view animates.
        Thread.sleep(forTimeInterval: 1)
        let tools = app.buttons.matching(NSPredicate(
            format: "identifier == 'style.sizes' OR identifier BEGINSWITH 'style.font.' OR identifier BEGINSWITH 'style.size.'"
        )).allElementsBoundByIndex.map(\.frame.minY) + [any("style.mic").frame.minY]
        let toolsTop = tools.min() ?? 0
        let headerBottom = app.buttons["keyboard.done"].frame.maxY
        XCTAssertLessThanOrEqual(field.frame.maxY, toolsTop + 0.5,
                                 "\(when): the block (\(field.frame)) runs under the text tools (top \(toolsTop))")
        XCTAssertGreaterThanOrEqual(field.frame.minY, headerBottom - 0.5,
                                    "\(when): the block (\(field.frame)) runs under the header (\(headerBottom))")
    }

    /// While a long paragraph is written, a drag on the page moves it and it
    /// stays where the finger left it: the block is kept clear of the tools
    /// when writing starts, when it grows and when the tools move, never
    /// against the user's own scroll.
    func testAScrollWhileWritingStaysWhereTheUserPutsIt() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(String(repeating: "We walked down to the river after lunch and sat on the warm stones. ",
                              count: 6))
        Thread.sleep(forTimeInterval: 1.5)
        let before = field.frame.maxY
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.2))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertGreaterThan(field.frame.maxY, before + 40,
                             "the page went back after the drag (block bottom \(before) -> \(field.frame.maxY))")
    }

    /// A drag takes the block under the text tools and the page stays
    /// there; a word typed on the same line (the block's height unchanged)
    /// brings the block back above the tools.
    func testTypingOnTheSameLineBringsTheBlockBack() {
        fillThePage()
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lunch by the river ")
        assertClearOfTheTools("a new block")
        let height = field.frame.height
        let toolsTop = any("style.mic").frame.minY
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertGreaterThan(field.frame.minY, toolsTop,
                             "the page stays where the drag left it (block \(field.frame), tools top \(toolsTop))")
        app.typeText("so")
        XCTAssertEqual(field.frame.height, height, accuracy: 0.5, "the words stayed on the same line")
        assertClearOfTheTools("a word typed on the same line")
    }

    /// A block taller than the band between the header and the tools
    /// follows the caret's line: a letter typed on its first line, dragged
    /// into view, keeps that line in view (it used to snap to the bottom).
    func testTypingHighInATallBlockKeepsTheCaretLineInView() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(String(repeating: "We walked down to the river after lunch and sat on the warm stones. ",
                              count: 14))
        Thread.sleep(forTimeInterval: 1.5)
        let headerBottom = app.buttons["keyboard.done"].frame.maxY
        // Drag the page down until the block's first line shows.
        for _ in 0..<6 where field.frame.minY < headerBottom + 20 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.2))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)))
            Thread.sleep(forTimeInterval: 1)
        }
        let firstLine = field.frame.minY
        XCTAssertGreaterThan(firstLine, headerBottom, "the first line shows (block \(field.frame))")
        field.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 30, dy: 12)).tap()
        app.typeText("Q")
        Thread.sleep(forTimeInterval: 1.5)

        let text = field.value as? String ?? ""
        XCTAssertTrue(text.prefix(30).contains("Q"), "the letter went into the first line: \(text.prefix(40))")
        let toolsTop = any("style.mic").frame.minY
        XCTAssertGreaterThanOrEqual(field.frame.minY, headerBottom - 0.5,
                                    "the first line went under the header (block \(field.frame))")
        XCTAssertLessThanOrEqual(field.frame.minY + 30, toolsTop,
                                 "the first line went under the tools (block \(field.frame), tools \(toolsTop))")
    }

    func testTheBlockBeingWrittenStaysAboveTheTextTools() {
        fillThePage()
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lunch by the river")
        assertClearOfTheTools("a new block")
        field.typeText(", then a long walk home with Sam and Jo under the golden light")
        assertClearOfTheTools("the block grown by typing")

        app.buttons["keyboard.done"].tap()
        let block = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'lunch by the river'")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        block.tap()
        if !field.exists { block.tap() }
        assertClearOfTheTools("the block opened again")
    }

    /// Owner's lead: after Done on a block that scrolled the page up to stay
    /// clear of the text tools, the page scrolls back to where it was before
    /// the writing began (the block may stay selected). A new block placed
    /// below the fold scrolls back only as far as keeps it in the card.
    func testDoneScrollsThePageBackToWhereItWas() {
        fillThePage()
        let photo = app.images.matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        let card = app.scrollViews.containing(.image, identifier: "element.image").firstMatch

        // A new block below the fold.
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lunch by the river")
        assertClearOfTheTools("a new block")
        let whileWriting = photo.frame.minY
        app.buttons["keyboard.done"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        let block = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'lunch by the river'")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(photo.frame.minY, whileWriting + 20, "Done scrolls the page back down")
        XCTAssertLessThanOrEqual(block.frame.maxY, card.frame.maxY + 0.5, "the finished block stays in the card")
        XCTAssertTrue(block.isHittable, "the finished block stays in reach")

        // A block in view, opened again: the tools cover it, the page
        // scrolls up, and Done brings it back exactly.
        let before = photo.frame.minY
        block.tap()
        if !field.exists { block.tap() }
        assertClearOfTheTools("the block opened again")
        XCTAssertLessThan(photo.frame.minY, before - 20, "the page scrolled up while writing")
        app.buttons["keyboard.done"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertEqual(photo.frame.minY, before, accuracy: 2, "Done scrolls the page back to where it was")
    }

    /// The text rows and the custom color sheet used along the way (the
    /// sheet lowers the keyboard and the tools move): Done still scrolls
    /// the page back.
    func testDoneScrollsBackAfterTheRowsAndTheColorSheet() {
        fillThePage()
        let photo = app.images.matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        let card = app.scrollViews.containing(.image, identifier: "element.image").firstMatch
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lunch by the river, then a long walk home")
        assertClearOfTheTools("a new block")
        let whileWriting = photo.frame.minY
        for row in ["style.colors", "style.highlight", "style.ai"] { app.buttons[row].tap() }
        app.buttons["style.colors"].tap()
        app.buttons["style.color.custom"].tap()
        XCTAssertTrue(app.buttons["colorSheet.apply"].waitForExistence(timeout: 5))
        app.buttons["colorSheet.apply"].tap()
        app.buttons["keyboard.done"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        let block = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'lunch by the river'")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(photo.frame.minY, whileWriting + 20, "Done scrolls the page back down")
        XCTAssertLessThanOrEqual(block.frame.maxY, card.frame.maxY + 0.5, "the finished block stays in the card")
        XCTAssertGreaterThan(block.frame.maxY, card.frame.maxY - 60, "and the page went back as far as that allows")
    }
}
