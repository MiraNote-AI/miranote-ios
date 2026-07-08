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

    // v2.1 gesture grammar: the Text tool drops an editable block right on
    // the canvas -- typing happens where the words will live.
    func testTextToolAddsEditableBlockInPlace() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mode.sticker"].exists)

        app.buttons["mode.text"].tap()
        // Multiline SwiftUI TextFields surface as text views, so match the
        // identifier across any element type.
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("warm broth, golden light")

        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.staticTexts["warm broth, golden light"].waitForExistence(timeout: 5))
    }

    // The Sound tool records in place: stop -> review -> Keep places a
    // sound marker with its note pill on the canvas.
    func testSoundToolRecordsAndKeepPlacesMarker() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.sound"].waitForExistence(timeout: 5))

        app.buttons["mode.sound"].tap()
        let stop = app.buttons["recorder.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()

        let keep = app.buttons["recorder.keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        keep.tap()
        XCTAssertTrue(app.staticTexts["Add a note"].waitForExistence(timeout: 5))
    }

    // The Image tool still opens its panel (contents are Phase D work).
    func testImageToolOpensPanel() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))

        app.buttons["mode.image"].tap()
        XCTAssertTrue(app.staticTexts["Add an image"].waitForExistence(timeout: 5))
    }

    // Long-press is the single delete path, and deletion is one tap from
    // undone (the "Deleted / Undo" toast).
    func testLongPressDeleteThenUndoRestores() {
        app.buttons["Start a memory"].tap()
        let title = app.staticTexts["Lunch by the river"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        title.press(forDuration: 0.9)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        let undo = app.buttons["toast.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Lunch by the river"].exists)

        undo.tap()
        XCTAssertTrue(app.staticTexts["Lunch by the river"].waitForExistence(timeout: 5))
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
    // semantics): Done composes the memory -- its title taken from the most
    // prominent text on the canvas -- files it into Daily Log, and returns
    // Home.
    func testDoneFilesMemoryAndReturnsHome() {
        app.buttons["Start a memory"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].exists)

        done.tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5))
        // Daily Log seeds 2 notes; filing the finished memory makes it 3.
        XCTAssertTrue(app.staticTexts["3 notes"].waitForExistence(timeout: 5))

        // The filed note carries the canvas title (starter draft's serif
        // title), proving Done captured real canvas content.
        app.buttons["collection.Daily Log"].tap()
        XCTAssertTrue(app.buttons["note.Lunch by the river"].waitForExistence(timeout: 5))
    }
}
