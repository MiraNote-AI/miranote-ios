import XCTest

/// #187 review: Layout waits while something is still on its way to the
/// page (Mira's turn, a clip being recorded, a photo edit kept running with
/// Done), a dimmed Layout says why on every Sticker panel tab, and Cancel and
/// the undo while trying put a long, scrolled page back where it stood
/// (46adcd0).
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

    private var photoFrames: [CGRect] {
        photos.allElementsBoundByIndex.map(\.frame).sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
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

    /// QA L5/L6.
    func testLayoutWaitsForMiraToFinish() {
        start(["-CHAT_DELAY", "8000"])
        addWords("A day by the sea")
        addPhotos(0..<3)
        XCTAssertTrue(app.buttons["mode.layout"].isEnabled)
        app.askMira("give this page a title")
        assertLayoutWaits("Layout waits for Mira to finish")
    }

    /// QA L5/L6: and the take stays live.
    func testLayoutWaitsForTheRecordingToFinish() {
        start()
        addWords("A day by the sea")
        addPhotos(0..<3)
        app.buttons["mode.voice"].tap()
        app.buttons["recorder.record"].tap()
        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 5))
        assertLayoutWaits("Layout waits for the recording to finish")
        XCTAssertTrue(app.buttons["recorder.stop"].exists, "the take is still being recorded")
        app.buttons["recorder.discard"].tap()
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

    // MARK: A long, scrolled page (46adcd0)

    func testCancelAndTheUndoWhileTryingPutALongScrolledPageBack() {
        start(["-SAMPLE_SHAPES"])
        addWords("A day by the sea")
        addPhotos(0..<3)
        addPhotos(3..<6)
        addWords("The last words at the foot of a long page")
        // The words just written are kept in view: the page stands scrolled.
        let title = app.staticTexts["A day by the sea"].firstMatch
        let titleY = title.frame.minY, frames = photoFrames
        XCTAssertLessThan(titleY, 0, "the page is scrolled down, its title above the screen")

        app.buttons["mode.layout"].tap()
        XCTAssertTrue(app.buttons["layout.template.magazine"].waitForExistence(timeout: 5))
        app.buttons["layout.template.magazine"].tap()
        settle()
        app.buttons["editor.undo"].tap()
        settle(1.5)
        assertPutBack(frames, titleY, "the undo while trying")

        app.buttons["layout.template.journal"].tap()
        settle()
        app.buttons["nav.leading"].tap()
        settle(1.5)
        assertPutBack(frames, titleY, "Cancel")
    }

    private func assertPutBack(_ frames: [CGRect], _ titleY: CGFloat, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let title = app.staticTexts["A day by the sea"].firstMatch
        XCTAssertEqual(title.frame.minY, titleY, accuracy: 1, "\(what): the page scrolled back", file: file, line: line)
        let now = photoFrames
        XCTAssertEqual(now.count, frames.count, file: file, line: line)
        for (put, was) in zip(now, frames) {
            XCTAssertEqual(put.minX, was.minX, accuracy: 1, "\(what): each photo back", file: file, line: line)
            XCTAssertEqual(put.minY, was.minY, accuracy: 1, "\(what): each photo back", file: file, line: line)
        }
    }
}
