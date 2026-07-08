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

    // The Library source adds real images through the store pipeline; they
    // render as canvas elements.
    func testLibraryAddsSamplePhotosToCanvas() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()

        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()

        // Back on the canvas: the starter placeholder plus two new photos.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        let firstImage = app.descendants(matching: .any).matching(identifier: "element.image").firstMatch
        XCTAssertTrue(firstImage.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            app.descendants(matching: .any).matching(identifier: "element.image").count, 3
        )
    }

    // Sticker creation lives inside Generate as a style: generating with the
    // sticker style and placing a result lands a sticker element and seeds
    // the favorites row.
    func testGenerateStickerPlacesElement() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()

        app.buttons["image.source.generate"].tap()
        // Pick the style before typing: once the keyboard is up it can
        // swallow taps meant for the chips row.
        let stickerStyle = app.buttons["image.style.sticker"]
        XCTAssertTrue(stickerStyle.waitForExistence(timeout: 5))
        stickerStyle.tap()

        let prompt = app.textFields["image.prompt"]
        prompt.tap()
        prompt.typeText("a coffee cup")
        app.buttons["image.generate.run"].tap()

        let firstResult = app.buttons["image.result.0"]
        XCTAssertTrue(firstResult.waitForExistence(timeout: 8))
        firstResult.tap()

        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        let sticker = app.descendants(matching: .any).matching(identifier: "element.sticker").firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 5), "the placed sticker renders on the canvas")
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
        // (The seed already contains a "Lunch by the river" note, so the
        // count is the only trustworthy signal here.)
        XCTAssertTrue(app.staticTexts["3 notes"].waitForExistence(timeout: 5))
    }

    // Mira applies a change atomically and shows the Keep-pattern receipt;
    // Revert is one tap and restores the original.
    func testMiraPolishShowsReceiptAndRevertRestores() {
        app.buttons["Start a memory"].tap()
        let input = app.textFields["mira.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("polish the text")
        app.buttons["mira.go"].tap()

        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 8))
        let polished = "(polished -- mock) Sunny afternoon, tiny noodle shop by the bridge"
        XCTAssertTrue(app.staticTexts[polished].waitForExistence(timeout: 3), "canvas text transformed")

        app.buttons["mira.revert"].tap()
        XCTAssertTrue(
            app.staticTexts["Sunny afternoon, tiny noodle shop by the bridge"].waitForExistence(timeout: 5),
            "revert restores the original text"
        )
    }

    // Past the threshold the bar shows verb-specific work with Stop; Stop
    // applies nothing and gives the words back.
    func testMiraStopRefillsPromptAndAppliesNothing() {
        app.buttons["Start a memory"].tap()
        let input = app.textFields["mira.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("think about this slowly")
        app.buttons["mira.go"].tap()

        let stop = app.buttons["mira.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "working bar appears with Stop")
        stop.tap()

        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "think about this slowly", "prompt refilled")
    }

    // Failure is a calm card with a retry chip; the prompt is refilled and
    // the canvas is untouched.
    func testMiraFailureShowsRetryAndRefills() {
        app.buttons["Start a memory"].tap()
        let input = app.textFields["mira.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("please fail now")
        app.buttons["mira.go"].tap()

        XCTAssertTrue(app.staticTexts["mira.failure"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["mira.retry"].exists)
        XCTAssertEqual(input.value as? String, "please fail now", "prompt refilled on failure")
        XCTAssertTrue(app.staticTexts["Sunny afternoon, tiny noodle shop by the bridge"].exists, "canvas untouched")
    }

    // With a selection, a vertical drag moves the element -- it must not be
    // stolen by the page scroll (the "selected moves, unselected scrolls"
    // grammar).
    func testDragMovesSelectedElementInsteadOfScrolling() {
        app.buttons["Start a memory"].tap()
        let title = app.staticTexts["Lunch by the river"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let before = title.frame.midY

        title.tap()
        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 140))
        start.press(forDuration: 0.08, thenDragTo: end)

        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(title.frame.midY, before + 70, "selected element follows the drag")
    }
}
