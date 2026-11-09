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

    private func settle() {
        _ = XCTWaiter().wait(for: [XCTestExpectation()], timeout: 0.8)
    }

    private func openLayout() {
        // Offered with nothing selected: a tap on bare paper lets go of the
        // title (again if the first tap lands while the page still settles).
        let entry = app.buttons["layout.open"]
        for _ in 0..<3 where !entry.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.42)).tap()
            _ = entry.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(entry.exists, "the layout entry shows on a bare canvas")
        entry.tap()
        XCTAssertTrue(app.buttons["layout.template.grid"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["nav.leading"].label, "Cancel")
        XCTAssertEqual(app.buttons["nav.trailing"].label, "Done")
    }

    func testDoneKeepsTheLayoutAsOneUndoStep() {
        let before = photoFrames
        openLayout()
        app.buttons["layout.template.collage"].tap()
        app.buttons["layout.template.grid"].tap()
        XCTAssertTrue(app.buttons["layout.template.grid"].isSelected)
        settle()
        let grid = photoFrames
        XCTAssertEqual(grid[0].minY, grid[1].minY, accuracy: 1, "two photos across the grid's first row")
        XCTAssertGreaterThan(grid[2].minY, grid[0].maxY, "the third starts the next row")

        app.buttons["nav.trailing"].tap()
        XCTAssertFalse(app.buttons["layout.template.grid"].exists, "the strip closes")
        XCTAssertTrue(app.buttons["mode.text"].exists, "the tool bar is back")
        settle()
        XCTAssertEqual(photoFrames, grid, "Done keeps the page as tried")

        app.buttons["editor.undo"].tap()
        settle()
        XCTAssertEqual(photoFrames, before, "one undo puts the page back")
    }

    func testCancelPutsThePageBack() {
        let before = photoFrames
        openLayout()
        app.buttons["layout.template.collage"].tap()
        settle()
        XCTAssertNotEqual(photoFrames, before, "the template shows on the page at once")
        app.buttons["nav.leading"].tap()
        settle()
        XCTAssertEqual(photoFrames, before)
        XCTAssertTrue(app.buttons["mode.text"].exists)
    }

    func testUndoWhileTryingGoesBackToThePageBefore() {
        let before = photoFrames
        openLayout()
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled, "nothing tried yet")
        app.buttons["layout.template.hero"].tap()
        settle()
        XCTAssertNotEqual(photoFrames, before)
        app.buttons["editor.undo"].tap()
        settle()
        XCTAssertEqual(photoFrames, before)
        XCTAssertTrue(app.buttons["layout.template.hero"].exists, "the strip stays open")
        XCTAssertFalse(app.buttons["layout.template.hero"].isSelected)
    }
}
