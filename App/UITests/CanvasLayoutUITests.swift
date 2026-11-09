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
}
