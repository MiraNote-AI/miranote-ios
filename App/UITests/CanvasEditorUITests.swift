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
        addTextBlock("golden broth by the window")
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].exists)

        done.tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5))
        // Daily Log seeds 2 notes; filing the finished memory makes it 3.
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

    // Long-press Edit photo opens the treatment panel; Make sticker runs
    // cutout + outline and replaces the photo with a sticker in place.
    func testPhotoEditMakeStickerReplacesInPlace() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()

        // The second element.image is a stored sample (the first is the
        // starter's pixel-less placeholder, which offers no Edit photo).
        let photo = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 1)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.press(forDuration: 0.9)

        let edit = app.buttons["Edit photo"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        app.buttons["photo.section.sticker"].tap()
        app.buttons["photo.makeSticker"].tap()

        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 8), "the photo became a sticker in place")
    }

    // With a selection, a vertical drag moves the element -- it must not be
    // stolen by the page scroll (the "selected moves, unselected scrolls"
    // grammar).
    func testDragMovesSelectedElementInsteadOfScrolling() {
        app.buttons["Start a memory"].tap()
        addTextBlock("drag me around")
        let title = app.staticTexts["drag me around"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let before = title.frame.midY

        title.tap()
        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 140))
        start.press(forDuration: 0.08, thenDragTo: end)

        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(title.frame.midY, before + 70, "selected element follows the drag")
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
