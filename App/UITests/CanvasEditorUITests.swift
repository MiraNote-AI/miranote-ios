import XCTest

/// UI tests for the canvas editor: tools, gestures, Mira turns, and the
/// image pipeline. Split from MiraNoteUITests for size.
final class CanvasEditorUITests: XCTestCase {
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

    // v2.1 gesture grammar: the Text tool drops an editable block right on
    // the canvas -- typing happens where the words will live.
    func testTextToolAddsEditableBlockInPlace() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))

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

    // The Voice tool records in place: Stop attaches the take as a marker
    // ("tap to play") and Keep closes the result sheet with it on the page.
    func testSoundToolRecordsAndKeepPlacesMarker() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.voice"].waitForExistence(timeout: 5))

        app.buttons["mode.voice"].tap()
        // The tool only arms the recorder -- nothing is captured until
        // the user presses Record.
        let record = app.buttons["recorder.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recorder.stop"].exists)
        record.tap()

        let stop = app.buttons["recorder.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()

        let keep = app.buttons["recorder.keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["tap to play"].exists, "attached before Keep (screen 09)")
        keep.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: keep)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["tap to play"].exists, "Keep leaves the marker on the page")

        // Selected, the marker offers its note.
        app.staticTexts["tap to play"].tap()
        XCTAssertTrue(app.staticTexts["Add a note"].waitForExistence(timeout: 5))
    }

    // The Image tool opens its "Choose photos" sheet over the live canvas
    // (screen 23).
    func testImageToolOpensPanel() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        addTextBlock("panel shows my page")

        app.buttons["mode.image"].tap()
        XCTAssertTrue(app.staticTexts["Choose photos"].waitForExistence(timeout: 5))

        // The page behind the sheet is the USER's live page -- their words
        // appear, the old catalog demo page does not.
        XCTAssertTrue(
            app.staticTexts["panel shows my page"].waitForExistence(timeout: 3),
            "image panel renders the live canvas"
        )
        XCTAssertFalse(
            app.staticTexts["Lunch by the river"].exists,
            "and never the demo content"
        )
    }

    // Long-press is the single delete path, and deletion is one tap from
    // undone (the "Deleted / Undo" toast).
    func testLongPressDeleteThenUndoRestores() {
        app.buttons["Start a memory"].tap()
        addTextBlock("delete me later")
        let title = app.staticTexts["delete me later"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        title.press(forDuration: 0.9)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        let undo = app.buttons["toast.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["delete me later"].exists)

        undo.tap()
        XCTAssertTrue(app.staticTexts["delete me later"].waitForExistence(timeout: 5))
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

        // On the live canvas: the two stored sample photos, the Image tool
        // still open (screen 25) until its header Add keeps them.
        let firstImage = app.descendants(matching: .any).matching(identifier: "element.image").firstMatch
        XCTAssertTrue(firstImage.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            app.descendants(matching: .any).matching(identifier: "element.image").count, 2
        )
        let add = app.buttons["nav.trailing"]
        XCTAssertEqual(add.label, "Add")
        add.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "element.image").count, 2)
    }

    // The bar carries the handoff's five tools; the Image sheet offers
    // Photo Library / Camera / AI Image (screen 23) and no generate styles;
    // no AI Sticker pill -- stickers are the fifth tool (owner, 2026-10-17).
    func testFiveToolsAndImageHasNoStickerStyle() {
        app.buttons["Start a memory"].tap()
        for tool in ["background", "voice", "text", "image", "sticker"] {
            XCTAssertTrue(app.buttons["mode.\(tool)"].waitForExistence(timeout: 5), tool)
        }
        XCTAssertFalse(app.buttons["mode.library"].exists, "Saved became Sticker")

        app.buttons["mode.image"].tap()
        XCTAssertTrue(app.buttons["image.library.open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["image.camera.open"].exists)
        XCTAssertEqual(app.buttons["image.source.generate"].label, "AI Image")
        XCTAssertFalse(app.buttons["image.style.photo"].exists)
        XCTAssertFalse(app.buttons["image.style.sticker"].exists)
        XCTAssertFalse(app.buttons["image.source.sticker"].exists, "no AI Sticker pill on the Image sheet")
        XCTAssertFalse(app.buttons["AI Sticker"].exists)
    }

    // Stickers are made in the Sticker tool. Add does not place the showing
    // result and does not file it in Favorites: the canvas asks where it
    // goes, and the next tap on the paper lands it there.
    func testGenerateStickerPlacesElement() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.sticker"].waitForExistence(timeout: 5))
        app.buttons["mode.sticker"].tap()

        let prompt = app.textFields["sticker.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("a coffee cup")
        app.buttons["sticker.generate.run"].tap()

        let firstResult = app.descendants(matching: .any).matching(identifier: "sticker.result.0").firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 8))
        let add = app.buttons["nav.trailing"]
        XCTAssertEqual(add.label, "Add")
        add.tap()

        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        let hint = app.staticTexts["canvas.place.hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "the canvas asks where it should go")

        // The paper carries no accessibility identifier on purpose (a container
        // id cascades onto the elements), so the placing tap goes by coordinate.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()

        let sticker = app.descendants(matching: .any).matching(identifier: "element.sticker").firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 5), "the tap placed the sticker on the canvas")
    }

    // Save round-trip (the save-does-not-wipe regression under autosave
    // semantics): Save -- the handoff's label for the canvas's trailing
    // pill -- composes the memory, its title taken from the most prominent
    // text on the canvas, files it into Daily Log, and returns Home.
    func testSaveFilesMemoryAndReturnsHome() {
        app.buttons["Start a memory"].tap()
        addTextBlock("golden broth by the window")
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Done"].exists, "the canvas header says Save, as drawn")

        save.tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5))
        // Daily Log seeds 2 notes; filing the finished memory makes it 3.
        // (Home cards no longer print a count -- screen 01 -- so count the
        // collection's covers.)
        app.buttons["collection.Daily Log"].tap()
        let covers = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'note.' AND identifier != 'note.add'"))
        XCTAssertTrue(covers.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(covers.count, 3)
    }

    // Mira applies a change atomically and shows the result sheet (screen
    // 07); Revert is one tap and restores the original.
    func testMiraPolishShowsReceiptAndRevertRestores() {
        app.buttons["Start a memory"].tap()
        addTextBlock("sunny afternoon by the bridge")

        app.askMira("polish the text")

        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 8))
        let polished = "(polished -- mock) sunny afternoon by the bridge"
        XCTAssertTrue(app.staticTexts[polished].waitForExistence(timeout: 3), "canvas text transformed")

        // The longer polished text re-fits its block instead of truncating:
        // two wrapped lines need meaningfully more height than one.
        XCTAssertGreaterThan(
            app.staticTexts[polished].frame.height, 50,
            "a Mira rewrite must grow the block with the words"
        )

        app.buttons["mira.revert"].tap()
        XCTAssertTrue(
            app.staticTexts["sunny afternoon by the bridge"].waitForExistence(timeout: 5),
            "revert restores the original text"
        )
    }

    // "Put this on the page" lands ONLY the current reply as one text
    // block -- never the running transcript the reply card displays.
    func testPlaceReplyPutsOnlyTheLastReplyOnThePage() {
        app.buttons["Start a memory"].tap()

        app.askMira("just chatting with you")

        let chip = app.buttons["Put this on the page"]
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "reply card shows the place chip")

        // Second turn: the card now shows a multi-message transcript.
        app.askMira("still just chatting")
        XCTAssertTrue(chip.waitForExistence(timeout: 8))

        chip.tap()

        // Exactly the quoted suggestion lands -- an exact label match
        // fails if the transcript or the chatty wrapping were glued in.
        XCTAssertTrue(
            app.staticTexts["a quiet line for the page"].waitForExistence(timeout: 5),
            "the placed block is the quoted suggestion only"
        )
        for chatter in ["just chatting with you", "still just chatting", "How about"] {
            XCTAssertFalse(
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS %@", chatter)
                ).firstMatch.exists,
                "conversation must not land on the page: \(chatter)"
            )
        }
    }

    // Past the threshold the bar shows verb-specific work with Stop; Stop
    // applies nothing and gives the words back.
    func testMiraStopRefillsPromptAndAppliesNothing() {
        app.buttons["Start a memory"].tap()
        app.askMira("think about this slowly")

        let stop = app.buttons["mira.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "working bar appears with Stop")
        stop.tap()

        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5))
        XCTAssertEqual(app.miraComposer.label, "think about this slowly", "prompt refilled")
        XCTAssertTrue(app.buttons["mira.go"].isEnabled, "the words wait, ready to send again")
    }

    // Failure is a calm card with a retry chip; the prompt is refilled and
    // the canvas is untouched.
    func testMiraFailureShowsRetryAndRefills() {
        app.buttons["Start a memory"].tap()
        addTextBlock("still here untouched")
        app.askMira("please fail now")

        XCTAssertTrue(app.staticTexts["mira.failure"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["mira.retry"].exists)
        XCTAssertEqual(app.miraComposer.label, "please fail now", "prompt refilled on failure")
        XCTAssertTrue(app.staticTexts["still here untouched"].exists, "canvas untouched")
    }

    // Long-press Edit photo lifts the photo into the editor; Cutout lifts
    // the subject and the photo becomes a sticker in place. AI Editing: one
    // instruction, new pixels in place, the editor stays on the result.
    func testPhotoAIEditRunsAndConfirms() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()

        let photo = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["Edit photo"].waitForExistence(timeout: 5))
        app.buttons["Edit photo"].tap()

        app.buttons["photo.tile.ai"].tap()
        let field = app.textFields["photo.prompt"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("make it autumn")
        app.buttons["photo.composer.action"].tap()

        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 8), .completed,
                       "the AI edit lands and the composer turns to Done")
        XCTAssertTrue(app.buttons["photo.undo"].isEnabled, "the edit is on the lifted photo")
        app.buttons["photo.composer.action"].tap()
        let done = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons["photo.undo"])
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 5), .completed, "Done closes the editor")
        let edited = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(edited.waitForExistence(timeout: 5), "the photo is still on the page")
        XCTAssertTrue(edited.isHittable, "the edited photo is on screen, no scrolling needed")
    }

    func testPhotoEditMakeStickerReplacesInPlace() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()

        // Both canvas images are stored samples now; take the first.
        let photo = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))

        // Consecutive photos sway instead of piling into one column.
        let second = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(
            abs(photo.frame.midX - second.frame.midX), 20,
            "added photos stagger like a hand-placed stack"
        )

        // The portrait sample gets an aspect-true box AND renders inside
        // it: 8x16 -> 170-wide box capped at 260 tall. A fill that leaks
        // its frame (the scaledToFill trap) would report ~340.
        XCTAssertEqual(second.frame.height, 260, accuracy: 8,
                       "portrait photos arrive tall and stay inside their box")

        photo.press(forDuration: 0.9)

        let edit = app.buttons["Edit photo"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        app.buttons["photo.tile.cutout"].tap()
        XCTAssertEqual(app.buttons["photo.composer.action"].label, "Edit")
        app.buttons["photo.composer.action"].tap()

        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 8), "the photo became a sticker in place")
    }

    // Pressing an unselected element and dragging moves it directly -- no
    // tap-to-select first (the "press to drag, long-press for menu"
    // grammar).
    func testDragMovesUnselectedElementDirectly() {
        app.buttons["Start a memory"].tap()
        addTextBlock("drag me around")
        let title = app.staticTexts["drag me around"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        // Closing the keyboard leaves the block selected; tap empty paper
        // to deselect -- the drag below must still move the element.
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: 300)).tap()
        let before = title.frame.midY

        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 140))
        start.press(forDuration: 0.08, thenDragTo: end)

        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(title.frame.midY, before + 70, "unselected element follows the drag")
    }

    /// Adds a text block through the Text tool and closes the keyboard.
    private func addTextBlock(_ text: String) {
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text)
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }
}
