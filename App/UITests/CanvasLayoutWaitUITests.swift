import XCTest

/// #187 review: Layout waits while something is still on its way to the
/// page, and a dimmed Layout says why on every Sticker panel tab.
final class CanvasLayoutWaitUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func start(_ arguments: [String] = []) {
        app.launchArguments = ["-UITEST"] + arguments
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private var photos: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "element.image")
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        _ = XCTWaiter().wait(for: [XCTestExpectation()], timeout: seconds)
    }

    private func addWords(_ words: String) {
        app.buttons["mode.text"].tap()
        let field = any("canvas.textEditor")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        settle()
    }

    /// Library photos `indices`, at most three per Add.
    private func addPhotos(_ indices: Range<Int>) {
        let target = photos.count + indices.count
        app.buttons["mode.image"].tap()
        let library = app.buttons["image.library.open"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        for index in indices {
            let cell = any("image.library.photo.\(index)")
            XCTAssertTrue(cell.waitForExistence(timeout: 5))
            cell.tap()
        }
        app.buttons["image.composer.add"].tap()
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == \(target)"), object: photos)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 8), .completed)
        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        settle()
    }

    /// Layout dims, and a tap says why and opens nothing.
    private func assertLayoutWaits(_ hint: String, file: StaticString = #filePath, line: UInt = #line) {
        let entry = app.buttons["mode.layout"]
        let dimmed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: entry)
        XCTAssertEqual(XCTWaiter().wait(for: [dimmed], timeout: 5), .completed, "Layout is dimmed",
                       file: file, line: line)
        entry.tap()
        XCTAssertTrue(app.staticTexts[hint].waitForExistence(timeout: 3), "the hint says why", file: file, line: line)
        XCTAssertFalse(app.buttons["layout.template.tShape"].exists, "the strip stays shut", file: file, line: line)
    }

    // MARK: Waits

    /// The edit lands through an undo step of the page as it is then: under
    /// a template being tried, Cancel put the old pixels back and left the
    /// template as the step below them.
    func testLayoutWaitsForAPhotoEditKeptRunning() {
        start(["-AI_EDIT_DELAY", "6000"])
        addWords("A day by the sea")
        addPhotos(0..<3)
        photos.allElementsBoundByIndex.last { $0.isHittable }?.press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["Edit photo"].waitForExistence(timeout: 5))
        app.buttons["Edit photo"].tap()
        XCTAssertTrue(app.buttons["photo.tile.ai"].waitForExistence(timeout: 5))
        app.buttons["photo.tile.ai"].tap()
        let field = app.textFields["photo.prompt"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("make it autumn")
        app.buttons["photo.composer.action"].tap()
        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.buttons["photo.filter.bw"].waitForNonExistence(timeout: 5),
                      "Done closes the editor, the edit runs on")

        assertLayoutWaits("Layout waits for the photo edit to finish")

        let entry = app.buttons["mode.layout"]
        let offered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: entry)
        XCTAssertEqual(XCTWaiter().wait(for: [offered], timeout: 15), .completed, "the edit landed: Layout again")
        entry.tap()
        XCTAssertTrue(app.buttons["layout.template.tShape"].waitForExistence(timeout: 5))
    }

    // MARK: The Sticker panel

    func testTheStickerPanelsDimmedLayoutSaysWhyOnEveryTab() {
        start()
        addWords("Only words")
        app.buttons["mode.sticker"].tap()
        XCTAssertTrue(app.buttons["sticker.tab.make"].waitForExistence(timeout: 5))
        let entry = app.buttons["mode.layout"]
        XCTAssertFalse(entry.isEnabled, "no photo: dimmed")
        let hint = app.staticTexts["Add a photo to use Layout"]
        for tab in ["food", "favorites", "make"] {
            app.buttons["sticker.tab.\(tab)"].tap()
            settle(0.4)
            entry.tap()
            XCTAssertTrue(hint.waitForExistence(timeout: 3), "the \(tab) tab says why")
            XCTAssertTrue(hint.isHittable, "on the \(tab) tab, in view")
            XCTAssertLessThan(hint.frame.maxY, entry.frame.minY, "above the tool bar on the \(tab) tab")
        }
    }
}
