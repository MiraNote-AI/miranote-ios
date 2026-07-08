import XCTest

/// UI regression tests for the Flow 7 redesign. The v1 interaction model
/// (empty-state hint, free-canvas long-press menu, sheet-based Save round-trip)
/// was replaced by the Home hero + a step-based editor with a bottom
/// instrument panel, so these assert the new flow instead.
final class MiraNoteUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Fresh, non-persistent seed each run so collection tests are stable.
        app.launchArguments = ["-UITEST"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // Home opens on the editorial hero with the primary action present.
    func testHomeShowsHeroAndStart() {
        XCTAssertTrue(app.staticTexts["MiraNote"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start a memory"].exists)
    }

    // The quick-capture field is a live text input, not a static placeholder:
    // typing and sending opens the MiraNote AI chat, seeded with the message.
    func testQuickCaptureOpensChat() {
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("noodles by the river")

        let send = app.buttons["quick.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        XCTAssertTrue(app.staticTexts["MiraNote AI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["noodles by the river"].waitForExistence(timeout: 5))
    }

    // Collections are real data: a seeded collection opens to its notes, and a
    // new note can be added and appears.
    func testOpenCollectionAndAddNote() {
        let dailyLog = app.buttons["collection.Daily Log"]
        XCTAssertTrue(dailyLog.waitForExistence(timeout: 5))
        dailyLog.tap()

        XCTAssertTrue(app.buttons["note.Lunch by the river"].waitForExistence(timeout: 5))

        app.buttons["note.add"].tap()
        XCTAssertTrue(app.buttons["note.New note"].waitForExistence(timeout: 5))
    }

    // Tapping a page opens reading mode (looking first); Edit is one tap
    // into the canvas editor carrying the same page.
    func testOpenPageReadsThenEdits() {
        app.buttons["collection.Daily Log"].tap()

        let cover = app.buttons["note.Lunch by the river"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        cover.tap()

        XCTAssertTrue(app.buttons["reading.share"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reading.edit"].exists)

        app.buttons["reading.edit"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5), "edit opens the canvas editor")
    }

    // The export sheet is destination-first: Save to Photos and Share lead;
    // a page with no sound shows no audio note.
    func testReadingShareShowsDestinations() {
        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.Lunch by the river"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        cover.tap()

        let share = app.buttons["reading.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()

        XCTAssertTrue(app.buttons["export.photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Share this page"].exists)
    }

    // Deleting a page from the journal grid sends it to the 30-day bin;
    // Restore brings it back.
    func testDeleteGoesToBinAndRestores() {
        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.Lunch by the river"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))

        cover.press(forDuration: 0.9)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertFalse(app.buttons["note.Lunch by the river"].exists)

        app.buttons["Home"].tap()
        let trashEntry = app.buttons["home.trash"]
        XCTAssertTrue(trashEntry.waitForExistence(timeout: 5))
        trashEntry.tap()

        let restore = app.buttons["trash.restore.Lunch by the river"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(app.staticTexts["Nothing waiting here."].waitForExistence(timeout: 5))
    }

    // From the chat, "New memory" files the conversation as a real note and
    // returns Home; the note then lives in the Daily Log collection.
    func testChatNewMemoryFilesToCollection() {
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("a quiet morning")
        app.buttons["quick.send"].tap()

        let newMemory = app.buttons["New memory"]
        XCTAssertTrue(newMemory.waitForExistence(timeout: 5))
        newMemory.tap()

        let dailyLog = app.buttons["collection.Daily Log"]
        XCTAssertTrue(dailyLog.waitForExistence(timeout: 5))
        dailyLog.tap()
        XCTAssertTrue(app.buttons["note.a quiet morning"].waitForExistence(timeout: 5))
    }

    // "Start a memory" opens the canvas editor: the page and the instrument
    // panel are shown.
    func testStartOpensCanvasEditor() {
        app.buttons["Start a memory"].tap()

        XCTAssertTrue(app.staticTexts["Lunch by the river"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mode.text"].exists)
        XCTAssertTrue(app.buttons["mode.image"].exists)
    }
}
