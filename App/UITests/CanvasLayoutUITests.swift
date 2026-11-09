import XCTest

/// #183: one-tap layouts. Templates are tried on the page as they are
/// tapped; Done keeps the last one as a single undo step, Cancel puts the
/// page back.
final class CanvasLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))

        app.buttons["mode.text"].tap()
        let field = any("canvas.textEditor")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("A day by the sea")
        app.buttons["keyboard.done"].tap()

        app.buttons["mode.image"].tap()
        let library = app.buttons["image.library.open"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        for n in 0..<3 {
            let cell = any("image.library.photo.\(n)")
            XCTAssertTrue(cell.waitForExistence(timeout: 5))
            cell.tap()
        }
        app.buttons["image.composer.add"].tap()
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 3"), object: photos)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 5), .completed)
        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private var photos: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "element.image")
    }

    private var photoFrames: [CGRect] {
        photos.allElementsBoundByIndex.map(\.frame).sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
    }

    /// The photos as placed on the page, wherever it is scrolled: measured
    /// from the title block, to a tenth of a point (the subtraction leaves
    /// float noise).
    private var photoPlaces: [CGRect] {
        let title = app.staticTexts["A day by the sea"].firstMatch.frame
        let tenth = { (value: CGFloat) in (value * 10).rounded() / 10 }
        return photoFrames.map {
            CGRect(x: tenth($0.minX - title.minX), y: tenth($0.minY - title.minY),
                   width: tenth($0.width), height: tenth($0.height))
        }
    }

    private func settle() {
        _ = XCTWaiter().wait(for: [XCTestExpectation()], timeout: 0.8)
    }

    private func openLayout() {
        let entry = app.buttons["mode.layout"]
        XCTAssertTrue(entry.isEnabled, "two elements or more: Layout can be tapped")
        entry.tap()
        XCTAssertTrue(app.buttons["layout.template.tShape"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["layout.template.grid2x2"].exists, "three photos: only templates for three")
        XCTAssertEqual(app.buttons["nav.leading"].label, "Cancel")
        XCTAssertEqual(app.buttons["nav.trailing"].label, "Done")
        XCTAssertTrue(entry.isSelected, "the tool bar stays, Layout lit")
        XCTAssertTrue(app.buttons["mode.text"].exists)
    }

    func testDoneKeepsTheLayoutAsOneUndoStep() {
        let before = photoPlaces
        openLayout()
        app.buttons["layout.template.onePlusTwo"].tap()
        app.buttons["layout.template.tShape"].tap()
        XCTAssertTrue(app.buttons["layout.template.tShape"].isSelected)
        settle()
        let grid = photoFrames
        XCTAssertGreaterThan(grid[0].width, grid[1].width * 1.5, "one wide photo across the top")
        XCTAssertEqual(grid[1].minY, grid[2].minY, accuracy: 1, "two squares under it")
        XCTAssertGreaterThan(grid[1].minY, grid[0].maxY)

        app.buttons["nav.trailing"].tap()
        XCTAssertFalse(app.buttons["layout.template.tShape"].exists, "the strip closes")
        XCTAssertTrue(app.buttons["mode.text"].exists, "the tool bar is back")
        settle()
        XCTAssertEqual(photoFrames, grid, "Done keeps the page as tried")

        // Done leaves the page where the layout showed it (its top), so
        // the undone page is compared as placed, not as scrolled.
        app.buttons["editor.undo"].tap()
        settle()
        XCTAssertEqual(photoPlaces, before, "one undo puts the page back")
    }

    func testCancelPutsThePageBack() {
        let before = photoFrames
        openLayout()
        app.buttons["layout.template.onePlusTwo"].tap()
        settle()
        XCTAssertNotEqual(photoFrames, before, "the template shows on the page at once")
        app.buttons["nav.leading"].tap()
        settle()
        XCTAssertEqual(photoFrames, before)
        XCTAssertTrue(app.buttons["mode.text"].exists)
    }

    func testLayoutIsDimmedWithFewerThanTwoElements() {
        app.terminate()
        app.launch()
        app.buttons["Start a memory"].tap()
        let entry = app.buttons["mode.layout"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertFalse(entry.isEnabled, "a blank page has nothing to arrange")
        app.buttons["mode.text"].tap()
        let field = any("canvas.textEditor")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Only words")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertFalse(entry.isEnabled, "one element: still nothing to arrange")
    }

    func testLayoutAgainOrAnotherToolPutsThePageBack() {
        let before = photoFrames
        openLayout()
        app.buttons["layout.template.onePlusTwo"].tap()
        settle()
        app.buttons["mode.layout"].tap()
        settle()
        XCTAssertFalse(app.buttons["layout.template.tShape"].exists, "Layout again closes the strip")
        XCTAssertFalse(app.buttons["mode.layout"].isSelected)
        XCTAssertEqual(photoFrames, before, "as Cancel")

        openLayout()
        app.buttons["layout.template.tShape"].tap()
        settle()
        app.buttons["mode.voice"].tap()
        settle()
        XCTAssertFalse(app.buttons["layout.template.tShape"].exists, "another tool closes it")
        XCTAssertEqual(photoFrames, before, "as Cancel")
    }

    func testUndoWhileTryingGoesBackToThePageBefore() {
        let before = photoFrames
        openLayout()
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled, "nothing tried yet")
        app.buttons["layout.template.tShape"].tap()
        settle()
        XCTAssertNotEqual(photoFrames, before)
        app.buttons["editor.undo"].tap()
        settle()
        XCTAssertEqual(photoFrames, before)
        XCTAssertTrue(app.buttons["layout.template.tShape"].exists, "the strip stays open")
        XCTAssertFalse(app.buttons["layout.template.tShape"].isSelected)
    }

    /// QA L1/L2: while the strip is open the page is a preview. A photo
    /// cannot be long-pressed (so not deleted) or dragged, and the next
    /// template still has every photo.
    func testThePageIsAPreviewWhileTheStripIsOpen() {
        openLayout()
        app.buttons["layout.template.onePlusTwo"].tap()
        settle()
        let tried = photoPlaces
        let photo = photos.element(boundBy: 0)
        photo.press(forDuration: 0.9)
        XCTAssertFalse(app.buttons["Delete"].waitForExistence(timeout: 1.5), "no element menu while previewing")
        let start = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.08, thenDragTo: start.withOffset(CGVector(dx: 60, dy: 80)))
        settle()
        XCTAssertEqual(photoPlaces, tried, "a drag moves nothing on the page")
        XCTAssertTrue(app.buttons["layout.template.onePlusTwo"].exists, "the strip stays open")

        app.buttons["layout.template.tShape"].tap()
        settle()
        XCTAssertEqual(photos.count, 3)
        app.buttons["nav.trailing"].tap()
        settle()
        XCTAssertEqual(photos.count, 3, "Done keeps every photo")
        photos.element(boundBy: 0).press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5), "after Done the page is live again")
    }

    /// QA L4/L5: a page with no photo dims Layout, and a tap on it says why.
    func testTheDimmedLayoutSaysWhyWhenTapped() {
        app.terminate()
        app.launch()
        app.buttons["Start a memory"].tap()
        let entry = app.buttons["mode.layout"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        for words in ["Only words", "And more words"] {
            app.buttons["mode.text"].tap()
            let field = any("canvas.textEditor")
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText(words)
            app.buttons["keyboard.done"].tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
        }
        XCTAssertFalse(entry.isEnabled, "two text blocks, no photo: nothing for a template to arrange")
        entry.tap()
        XCTAssertTrue(app.staticTexts["Add a photo to use Layout"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["layout.template.strip"].exists, "the strip does not open")
    }

    /// QA L12: reopened on a page a template laid out, the strip marks it.
    func testReopeningTheStripMarksTheTemplateInUse() {
        openLayout()
        XCTAssertFalse(app.buttons["layout.template.tShape"].isSelected, "a page as placed by hand: none")
        app.buttons["layout.template.tShape"].tap()
        app.buttons["nav.trailing"].tap()
        settle()
        openLayout()
        XCTAssertTrue(app.buttons["layout.template.tShape"].isSelected)
        XCTAssertFalse(app.buttons["layout.template.onePlusTwo"].isSelected)
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled, "nothing tried yet")
    }
}
