import XCTest

/// Handoff screens 27-28: a lifted photo offers a floating Undo, a held (or
/// tapped) split compare against how it was when editing began, and Cancel
/// puts it back that way in one undoable step.
final class PhotoRevertUITests: XCTestCase {
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

    private var compare: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "photo.compare").firstMatch
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Samples land two photos and the Image tool stays open (screen 25).
    private func placeSamples() -> XCUIElement {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        let photo = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        return photo
    }

    private func openEditor(_ photo: XCUIElement) {
        photo.press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["Edit photo"].waitForExistence(timeout: 5))
        app.buttons["Edit photo"].tap()
        XCTAssertTrue(app.buttons["photo.filter.bw"].waitForExistence(timeout: 5))
    }

    private func waitGone(_ element: XCUIElement, _ message: String) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, message)
    }

    func testCancelPutsThePhotoBackAndUndoReturnsTheEdit() {
        let photo = placeSamples()
        openEditor(photo)

        let undo = app.buttons["photo.undo"]
        XCTAssertFalse(undo.isEnabled, "nothing to undo before an edit")

        app.buttons["photo.filter.bw"].tap()
        XCTAssertTrue(app.buttons["photo.filter.bw"].isSelected)
        XCTAssertTrue(undo.isEnabled, "the edit can be taken back")
        compare.press(forDuration: 0.6)
        XCTAssertFalse(any("photo.before").exists, "letting go shows the edit again")

        app.buttons["Cancel"].tap()
        waitGone(app.buttons["photo.filter.bw"], "Cancel closes the editor")

        // The photo is its original again: the reopened editor has nothing
        // to undo and no filter on.
        openEditor(photo)
        XCTAssertFalse(app.buttons["photo.filter.bw"].isSelected, "back to the original look")
        XCTAssertFalse(app.buttons["photo.undo"].isEnabled)
        app.buttons["photo.composer.action"].tap()
        waitGone(app.buttons["photo.filter.bw"], "Done closes the editor")

        app.buttons["Undo"].tap()
        openEditor(photo)
        XCTAssertTrue(app.buttons["photo.filter.bw"].isSelected, "one undo brings the edit back")
    }

    func testFloatingUndoTakesBackOneEdit() {
        let photo = placeSamples()
        openEditor(photo)
        app.buttons["photo.filter.bw"].tap()
        XCTAssertTrue(app.buttons["photo.filter.bw"].isSelected)

        app.buttons["photo.undo"].tap()
        XCTAssertFalse(app.buttons["photo.filter.bw"].isSelected, "the floating Undo took the filter off")
        XCTAssertFalse(app.buttons["photo.undo"].isEnabled, "and nothing of this session is left to undo")
    }

    // Screen 28: Before and Current side by side while compare is on.
    func testCompareShowsBeforeAndCurrentSideBySide() {
        let photo = placeSamples()
        openEditor(photo)
        app.buttons["photo.filter.bw"].tap()

        compare.tap()
        XCTAssertTrue(any("photo.before").waitForExistence(timeout: 3), "a tap pins the split view")
        XCTAssertTrue(any("photo.current").exists)
        XCTAssertLessThan(any("photo.before").frame.midX, any("photo.current").frame.midX,
                          "Before on the left, Current on the right")
        XCTAssertEqual(compare.value as? String, "Showing before and current")

        compare.tap()
        waitGone(any("photo.before"), "a second tap lets go")
        XCTAssertEqual(compare.value as? String, "Showing your edit")
    }

    // Screens 27-28: the tile picks what the composer asks and does.
    func testTilesSetTheComposer() {
        let photo = placeSamples()
        openEditor(photo)
        let action = app.buttons["photo.composer.action"]
        XCTAssertEqual(action.label, "Done", "instant tiles: the composer closes")

        app.buttons["photo.tile.ai"].tap()
        XCTAssertTrue(app.buttons["photo.tile.ai"].isSelected)
        XCTAssertEqual(action.label, "Edit")
        XCTAssertFalse(action.isEnabled, "AI Editing waits for words")
        XCTAssertTrue(app.textFields["photo.prompt"].exists)

        app.buttons["photo.tile.cutout"].tap()
        XCTAssertTrue(app.buttons["photo.tile.cutout"].isSelected)
        XCTAssertFalse(app.buttons["photo.tile.ai"].isSelected)
        XCTAssertTrue(action.isEnabled, "a cutout target is optional")

        // The extra tiles after the design's four are still there.
        for id in ["photo.filter.match", "photo.filter.warm", "photo.filter.film", "photo.frame.polaroid"] {
            XCTAssertTrue(app.buttons[id].exists, id)
        }
    }

    // An AI edit stays on the lifted photo (screen 28). Done keeps it: a
    // later visit's Undo and Cancel discard only that visit's own edits
    // (owner decision; this test used to codify Cancel reverting to the
    // first visit's original). Compare still shows the photo as it came.
    func testALaterVisitKeepsAnEditConfirmedWithDone() {
        let photo = placeSamples()
        openEditor(photo)
        app.buttons["photo.tile.ai"].tap()
        let field = app.textFields["photo.prompt"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("make it autumn")
        app.buttons["photo.composer.action"].tap()

        let undo = app.buttons["photo.undo"]
        let edited = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: undo)
        XCTAssertEqual(XCTWaiter().wait(for: [edited], timeout: 8), .completed, "the AI edit landed")
        XCTAssertEqual(app.buttons["photo.composer.action"].label, "Done", "the composer turns to Done")
        app.buttons["photo.composer.action"].tap()
        waitGone(undo, "Done closes the editor")

        openEditor(photo)
        XCTAssertFalse(app.buttons["photo.undo"].isEnabled, "the kept AI edit is not this visit's to undo")
        app.buttons["photo.filter.bw"].tap()
        XCTAssertTrue(app.buttons["photo.undo"].isEnabled, "this visit's own edit is")
        app.buttons["Cancel"].tap()
        waitGone(app.buttons["photo.filter.bw"], "Cancel closes the editor")

        openEditor(photo)
        XCTAssertFalse(app.buttons["photo.filter.bw"].isSelected, "Cancel took this visit's B&W back")
        compare.tap()
        XCTAssertTrue(any("photo.before").waitForExistence(timeout: 3),
                      "and kept the AI edit: the photo still differs from how it came")
    }

    // The floating Undo never takes back another element's step: Meng's
    // probe (B&W, Done, a text block, reopen, Undo) lost the text block.
    func testTheFloatingUndoLeavesANewerTextBlock() {
        let photo = placeSamples()
        openEditor(photo)
        app.buttons["photo.filter.bw"].tap()
        app.buttons["photo.composer.action"].tap()
        let add = app.buttons["nav.trailing"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Dinner with Mom")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.staticTexts["Dinner with Mom"].waitForExistence(timeout: 5))

        openEditor(photo)
        let undo = app.buttons["photo.undo"]
        XCTAssertFalse(undo.isEnabled, "the newest step is the text block's")
        undo.tap()
        XCTAssertTrue(app.buttons["photo.filter.bw"].isSelected, "the B&W stays")
        app.buttons["photo.composer.action"].tap()
        XCTAssertTrue(app.staticTexts["Dinner with Mom"].waitForExistence(timeout: 5), "and so does the text")
    }

    // A change made while the editor was closed -- here Mira's black and
    // white from the bar -- is not the reopened editor's to revert: Cancel
    // takes back the frame and keeps Mira's edit (#102).
    func testCancelKeepsAMiraEditMadeWhileTheEditorWasClosed() {
        let photo = placeSamples()
        openEditor(photo)
        app.buttons["photo.composer.action"].tap()
        // The header's Add keeps the placed photos and closes the Image tool.
        let add = app.buttons["nav.trailing"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertEqual(add.label, "Add")
        add.tap()

        photo.tap()
        app.askMira("make the photo black and white")
        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 5))

        openEditor(photo)
        let blackAndWhite = app.buttons["photo.filter.bw"]
        XCTAssertTrue(blackAndWhite.isSelected, "Mira's edit shows in the editor")
        XCTAssertFalse(app.buttons["photo.undo"].isEnabled, "and is not this editor's to take back")

        app.buttons["photo.frame.polaroid"].tap()
        XCTAssertTrue(app.buttons["photo.undo"].isEnabled)
        app.buttons["Cancel"].tap()

        openEditor(photo)
        XCTAssertTrue(app.buttons["photo.filter.bw"].isSelected, "Cancel kept Mira's black and white")
        XCTAssertFalse(app.buttons["photo.frame.polaroid"].isSelected, "and took the frame back")
    }
}
