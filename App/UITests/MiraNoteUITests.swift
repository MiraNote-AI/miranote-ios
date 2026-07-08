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

        XCTAssertTrue(app.staticTexts["Lunch by the river"].waitForExistence(timeout: 5))

        app.buttons["note.add"].tap()
        XCTAssertTrue(app.staticTexts["New note"].waitForExistence(timeout: 5))
    }

    // Tapping a note opens it in an editor with its title loaded and an
    // editable body.
    func testOpenNoteOpensEditor() {
        app.buttons["collection.Daily Log"].tap()

        let noteRow = app.buttons["note.Lunch by the river"]
        XCTAssertTrue(noteRow.waitForExistence(timeout: 5))
        noteRow.tap()

        let titleField = app.textFields["note.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertEqual(titleField.value as? String, "Lunch by the river")
        XCTAssertTrue(app.textViews["note.body"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["a quiet morning"].waitForExistence(timeout: 5))
    }

    // "Start a memory" opens the canvas editor: the page and the instrument
    // panel are shown.
    func testStartOpensCanvasEditor() {
        app.buttons["Start a memory"].tap()

        XCTAssertTrue(app.staticTexts["Lunch by the river"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mode.text"].exists)
        XCTAssertTrue(app.buttons["mode.image"].exists)
    }

    // The instrument panel switches the editor between the three v2.1 input
    // scenes; sticker is no longer a mode on the bar.
    func testInputModeSwitchesScenes() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mode.sticker"].exists)

        app.buttons["mode.text"].tap()
        XCTAssertTrue(app.staticTexts["Text input"].waitForExistence(timeout: 5))

        app.buttons["mode.image"].tap()
        XCTAssertTrue(app.staticTexts["Add an image"].waitForExistence(timeout: 5))

        app.buttons["mode.sound"].tap()
        XCTAssertTrue(app.staticTexts["Sound"].waitForExistence(timeout: 5))
    }

    // Sticker creation moved inside the Image panel: Generate opens the
    // sticker creator.
    func testGenerateOpensStickerCreator() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))

        app.buttons["mode.image"].tap()
        let generate = app.buttons["image.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))

        generate.tap()
        XCTAssertTrue(app.staticTexts["Create sticker"].waitForExistence(timeout: 5))
    }

    // Done round-trip (the save-does-not-wipe regression under autosave
    // semantics): Done files the memory into Daily Log and returns Home.
    func testDoneFilesMemoryAndReturnsHome() {
        app.buttons["Start a memory"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].exists)

        done.tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5))
        // Daily Log seeds 2 notes; filing the finished memory makes it 3.
        XCTAssertTrue(app.staticTexts["3 notes"].waitForExistence(timeout: 5))
    }
}
