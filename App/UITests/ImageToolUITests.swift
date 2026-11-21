import XCTest

/// The Image tool in place over the canvas (handoff screens 23-26, #205):
/// Choose photos, the Recents grid with ordered picks, the composer's Add
/// that lands them and closes the tool, one Undo for the batch, and
/// "Editing" for a single pick. The header is Home (greyed) / Undo / Save
/// (greyed) while the tool is open. -UITEST reads 120 painted samples
/// instead of the photo library.
final class ImageToolUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func canvasState() -> [String: Any] {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let data = probe.label.data(using: .utf8) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private var photos: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "element.image")
    }

    /// E3A, F1A: Home and Save greyed while the Image tool is open, Undo
    /// live; no Add in the header.
    private func assertToolHeader(_ context: String) {
        XCTAssertEqual(app.buttons["nav.leading"].label, "Home", context)
        XCTAssertFalse(app.buttons["nav.leading"].isEnabled, context)
        XCTAssertEqual(app.buttons["nav.trailing"].label, "Save", context)
        XCTAssertFalse(app.buttons["nav.trailing"].isEnabled, context)
    }

    private func openRecents() {
        let library = app.buttons["image.library.open"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        assertToolHeader("Choose photos")
        library.tap()
        XCTAssertTrue(any("image.library.photo.0").waitForExistence(timeout: 5))
    }

    func testPicksAreCountedInOrderAndAddClosesTheTool() {
        openRecents()
        assertToolHeader("Recents")
        XCTAssertFalse(app.buttons["image.composer.add"].isEnabled, "Add waits for a pick")

        any("image.library.photo.0").tap()
        any("image.library.photo.2").tap()
        any("image.library.photo.5").tap()
        XCTAssertEqual(app.staticTexts["image.library.count"].label, "3 selected")
        XCTAssertTrue(any("image.library.photo.2").isSelected)

        // Unpicking renumbers the rest.
        any("image.library.photo.2").tap()
        XCTAssertEqual(app.staticTexts["image.library.count"].label, "2 selected")

        app.buttons["image.composer.add"].tap()
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: photos)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 5), .completed, "both picks landed")
        // F10A: the tool closes, back on the page with the last one selected.
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "Add closes the tool")
        XCTAssertFalse(any("image.library.grid").exists, "the sheet folds away")
        XCTAssertFalse(app.buttons["mode.image"].isSelected)
        XCTAssertTrue(app.buttons["nav.leading"].isEnabled, "Home is live again")
        XCTAssertTrue(app.buttons["nav.trailing"].isEnabled, "Save is live again")
        XCTAssertEqual(photos.count, 2)
        let state = canvasState()
        let images = (state["elements"] as? [[String: Any]] ?? []).filter { $0["kind"] as? String == "image" }
        XCTAssertEqual(state["selected"] as? String, images.last?["id"] as? String, "the last photo is selected")
    }

    /// Leaving without adding: the lit Image tool goes back to Choose photos,
    /// dropping the picks, then shuts; nothing lands.
    func testTheImageToolAgainLeavesTheLibraryWithoutAdding() {
        openRecents()
        any("image.library.photo.0").tap()
        app.buttons["mode.image"].tap()
        XCTAssertTrue(any("image.library.grid").waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["image.library.open"].waitForExistence(timeout: 5), "back on Choose photos")
        app.buttons["mode.image"].tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["nav.leading"].label, "Home", "the bare canvas")
        XCTAssertTrue(app.buttons["nav.leading"].isEnabled)
        XCTAssertFalse(app.buttons["mode.image"].isSelected)
        XCTAssertEqual(photos.count, 0, "the pick was let go")
    }

    /// #167: photos land under everything else on the page; on a long
    /// page scrolled to the top the canvas scrolls down to show them.
    func testAddedPhotosComeIntoViewOnALongPage() {
        app.buttons["mode.image"].tap()
        app.buttons["mode.text"].tap()
        let field = any("canvas.textEditor")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Top" + String(repeating: "\nline", count: 45))
        app.buttons["keyboard.done"].tap()
        for _ in 0..<4 { app.swipeDown() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Top'")).firstMatch.isHittable,
                      "the page is scrolled to its top")

        app.buttons["mode.image"].tap()
        openRecents()
        any("image.library.photo.0").tap()
        app.buttons["image.composer.add"].tap()
        let photo = photos.firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: photo)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 5), .completed, "the canvas scrolled to the photo")
    }

    /// #167: long-press a Recents photo and drag it onto the page: it lands
    /// where it was let go, the sheet stays for the next one, and a drop
    /// back on the sheet places nothing.
    func testALongPressedPhotoDragsStraightOntoThePage() {
        openRecents()
        let cell = any("image.library.photo.1")
        let grid = any("image.library.grid")

        // Let go on the sheet itself: nothing lands.
        cell.press(forDuration: 0.6, thenDragTo: any("image.library.photo.4"))
        sleep(1)
        XCTAssertEqual(photos.count, 0, "a drop on the sheet places nothing")

        let target = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width * 0.3, dy: grid.frame.minY - 160))
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.6, thenDragTo: target)
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"), object: photos)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 5), .completed, "the photo landed")
        let photo = photos.firstMatch
        XCTAssertLessThan(abs(photo.frame.midX - target.screenPoint.x), 40, "where it was let go (x)")
        XCTAssertLessThan(abs(photo.frame.midY - target.screenPoint.y), 40, "where it was let go (y)")
        XCTAssertTrue(grid.exists, "Recents stays open for the next one")
        XCTAssertFalse(cell.isSelected, "dragging is not picking")

        XCTAssertTrue(app.buttons["editor.undo"].isEnabled, "the header Undo takes a drop back")
        app.buttons["editor.undo"].tap()
        XCTAssertEqual(photos.count, 0, "Undo took the dropped photo back")
        XCTAssertTrue(grid.exists, "and Recents stays open")
    }

    /// #178 review: an import landing while a photo is carried closes
    /// Recents and cancels the drag; the carried photo must not stay over
    /// the canvas.
    func testAnImportLandingMidCarryLeavesNoCarriedPhoto() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-IMPORT_DELAY", "3000"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        openRecents()
        let grid = any("image.library.grid")
        any("image.library.photo.0").tap()
        app.buttons["image.composer.add"].tap()

        // Hold another photo over the page until the import lands.
        let target = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width * 0.3, dy: grid.frame.minY - 160))
        any("image.library.photo.1").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.6, thenDragTo: target, withVelocity: 600, thenHoldForDuration: 4)
        XCTAssertFalse(grid.exists, "the import landed mid-carry and closed Recents")
        sleep(1)
        XCTAssertEqual(photos.count, 1, "only the added pick landed")
        XCTAssertEqual(canvasState()["photoDragging"] as? Bool, false,
                       "the carried photo stayed over the canvas")
    }

    /// A slow import (held 4 s): the composer Add tapped twice lands the
    /// picks once, and Add / Editing wait out the import.
    func testASecondAddDuringASlowImportAddsNothingTwice() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-IMPORT_DELAY", "4000"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        openRecents()
        any("image.library.photo.0").tap()
        any("image.library.photo.1").tap()
        let add = app.buttons["image.composer.add"]
        add.tap()
        XCTAssertFalse(add.isEnabled, "Add waits while the picks import")
        add.tap()
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: photos)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 8), .completed)
        sleep(5)
        XCTAssertEqual(photos.count, 2, "the picks landed twice")
    }

    /// One pick importing, then Editing again: one photo lands.
    func testEditingDuringASlowImportIsDisabled() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-IMPORT_DELAY", "4000"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        openRecents()
        any("image.library.photo.0").tap()
        app.buttons["image.library.editing"].tap()
        XCTAssertFalse(app.buttons["image.library.editing"].isEnabled, "Editing waits while the pick imports")
        app.buttons["image.library.editing"].tap()
        XCTAssertTrue(app.buttons["photo.filter.bw"].waitForExistence(timeout: 8), "the pick lifts into the editor")
        sleep(5)
        XCTAssertEqual(photos.count, 1, "the pick landed twice")
    }

    /// G8: one Undo takes back the whole batch one Add placed.
    func testOneUndoTakesBackTheWholeAdd() {
        openRecents()
        any("image.library.photo.0").tap()
        any("image.library.photo.1").tap()
        any("image.library.photo.2").tap()
        app.buttons["image.composer.add"].tap()
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 3"), object: photos)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 5), .completed)
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5))
        XCTAssertEqual(canvasState()["undoDepth"] as? Int, 1, "one step for the batch")

        app.buttons["editor.undo"].tap()
        XCTAssertEqual(photos.count, 0, "one undo took all three back")
    }

    // Limited library access: the grid shows the photos the user shared,
    // and the sheet offers more -- the system's limited picker, or the
    // system photo picker for a one-off pick.
    func testLimitedAccessOffersTheOtherPhotos() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-PHOTOS-LIMITED"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        openRecents()

        XCTAssertEqual(app.buttons["image.library.more"].label, "Add to Library", "share more photos with MiraNote")
        XCTAssertEqual(app.buttons["image.library.system"].label, "Add to Canvas", "or pick any photo once")
        XCTAssertTrue(any("image.library.photo.0").isHittable, "the shared photos are still the grid")
    }

    // The same two buttons in Chinese say where the photos go: into the
    // library, or onto the page (#167).
    func testLimitedAccessButtonsSayWhereThePhotosGoInChinese() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-PHOTOS-LIMITED", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        let library = app.buttons["image.library.open"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()

        let more = app.buttons["image.library.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertEqual(more.label, "\u{52A0}\u{5165}\u{56FE}\u{5E93}")
        XCTAssertEqual(app.buttons["image.library.system"].label, "\u{653E}\u{5230}\u{753B}\u{5E03}")
    }
}

// MARK: AI Image (screen 23's third pill)

extension ImageToolUITests {
    private func relaunch(_ arguments: [String]) {
        app.terminate()
        app.launchArguments = ["-UITEST"] + arguments
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
    }

    /// AI Image switches the composer to a prompt; Generate runs.
    private func generate(_ words: String) {
        let pill = app.buttons["image.source.generate"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the sheet's third pill")
        XCTAssertEqual(pill.label, "AI Image")
        pill.tap()
        let prompt = app.textFields["image.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "the composer takes words")
        XCTAssertEqual(prompt.placeholderValue, "Describe an image")
        XCTAssertFalse(app.buttons["image.generate.run"].isEnabled, "nothing to generate yet")
        assertToolHeader("AI Image, nothing waiting")
        prompt.tap()
        prompt.typeText(words)
        app.buttons["image.generate.run"].tap()
    }

    private func waitForPhotos(_ count: Int, timeout: TimeInterval = 5) -> Bool {
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == \(count)"), object: photos)
        return XCTWaiter().wait(for: [landed], timeout: timeout) == .completed
    }

    func testAIImageGeneratesCandidatesAndAPickLandsOnThePage() {
        generate("a lighthouse at dawn")
        let first = app.buttons["image.result.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "the candidates arrive")
        XCTAssertTrue(app.buttons["image.result.1"].exists)
        XCTAssertEqual(photos.count, 0, "nothing lands before a pick")

        first.tap()
        XCTAssertTrue(waitForPhotos(1), "the pick is on the page")
        XCTAssertFalse(app.buttons["image.result.1"].exists, "the other candidate goes")
        // G9: the pick closes the tool, like a sticker.
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "the pick closes the tool")
        XCTAssertEqual(photos.count, 1)
        app.buttons["Undo"].tap()
        XCTAssertEqual(photos.count, 0, "one undo step takes it back")
    }

    /// Candidates waiting: as a made sticker waiting (H2), the leading
    /// pill is Cancel and lets them go; Save stays greyed.
    func testCancelLetsTheCandidatesGo() {
        generate("a lighthouse at dawn")
        XCTAssertTrue(app.buttons["image.result.0"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["nav.leading"].label, "Cancel")
        XCTAssertTrue(app.buttons["nav.leading"].isEnabled)
        XCTAssertFalse(app.buttons["nav.trailing"].isEnabled, "Save stays greyed")
        app.buttons["nav.leading"].tap()
        XCTAssertFalse(app.buttons["image.result.0"].exists, "the candidates are gone")
        XCTAssertTrue(app.buttons["image.library.open"].waitForExistence(timeout: 5), "back on Choose photos")
        XCTAssertEqual(photos.count, 0, "nothing was added")
    }

    /// A slow painting: another tool cannot drop it, it arrives once, and
    /// the pick lands once.
    func testASlowGenerationSurvivesAToolSwitch() {
        relaunch(["-GENERATE_DELAY", "3000"])
        generate("a lighthouse at dawn")
        XCTAssertTrue(any("image.generating").waitForExistence(timeout: 3), "the working state shows")
        app.buttons["mode.text"].tap()
        XCTAssertTrue(app.staticTexts["image.notice"].waitForExistence(timeout: 3), "the switch says why it waits")
        XCTAssertFalse(any("canvas.textEditor").exists, "no text block opened over the painting")
        app.buttons["mode.sticker"].tap()
        XCTAssertFalse(app.textFields["sticker.prompt"].waitForExistence(timeout: 2), "still in the Image tool")

        XCTAssertTrue(app.buttons["image.result.0"].waitForExistence(timeout: 8), "the painting arrives")
        XCTAssertTrue(app.buttons["image.result.1"].exists)
        XCTAssertFalse(app.buttons["image.result.2"].exists, "once, not twice")
        app.buttons["image.result.0"].tap()
        XCTAssertTrue(waitForPhotos(1))
        sleep(2)
        XCTAssertEqual(photos.count, 1, "the pick landed twice")
    }

    /// The Image tool again while a painting is on its way or waits: it
    /// says so and stays, the painting is not dropped; Save stays greyed.
    func testTheImageToolAgainWhileAPaintingWaitsSaysSoAndStays() {
        relaunch(["-GENERATE_DELAY", "3000"])
        generate("a lighthouse at dawn")
        XCTAssertTrue(any("image.generating").waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["nav.trailing"].isEnabled, "no Save over a painting on its way")
        app.buttons["mode.image"].tap()
        XCTAssertTrue(app.staticTexts["image.notice"].waitForExistence(timeout: 3), "the tool says why it waits")
        XCTAssertTrue(app.buttons["image.result.0"].waitForExistence(timeout: 8), "the painting still arrives")
        app.buttons["mode.image"].tap()
        XCTAssertTrue(app.staticTexts["image.notice"].waitForExistence(timeout: 3), "a waiting pick holds it too")
        XCTAssertTrue(app.buttons["image.result.0"].exists, "the candidates stay")
        XCTAssertEqual(photos.count, 0)
    }

    /// While a painting is on its way, Edit photo does not open over it (its
    /// tool bar would be dead, every tap swallowed for the hidden painting):
    /// the AI Image sheet says why and stays.
    func testEditPhotoWaitsForAPaintingOnItsWay() {
        relaunch(["-GENERATE_DELAY", "4000"])
        app.buttons["image.library.open"].tap()
        XCTAssertTrue(any("image.library.photo.0").waitForExistence(timeout: 5))
        any("image.library.photo.0").tap()
        app.buttons["image.composer.add"].tap()
        let photo = photos.firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "Add closed the tool")
        app.buttons["mode.image"].tap()
        generate("a lighthouse at dawn")
        XCTAssertTrue(any("image.generating").waitForExistence(timeout: 3))

        photo.press(forDuration: 0.9)
        let edit = app.buttons["Edit photo"]
        if edit.waitForExistence(timeout: 3) { edit.tap() }
        XCTAssertFalse(app.buttons["photo.tile.ai"].waitForExistence(timeout: 2), "the photo editor did not open")
        XCTAssertTrue(app.staticTexts["image.notice"].waitForExistence(timeout: 3), "the sheet says why")
        XCTAssertTrue(app.buttons["image.result.0"].waitForExistence(timeout: 8), "the painting still arrives")
    }

    /// The prompt's keyboard comes down on a tap on the sheet or the page,
    /// without generating; the words and the sheet stay (#120's rule).
    func testATapOnTheSheetOrThePageLowersTheAIImageKeyboard() {
        let pill = app.buttons["image.source.generate"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        pill.tap()
        let prompt = app.textFields["image.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("a lighthouse")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)

        app.staticTexts["AI Image"].tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), "a tap on the sheet lowers the keyboard")
        XCTAssertEqual(prompt.value as? String, "a lighthouse", "the words stay")

        prompt.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 4))
        let header = app.buttons["nav.leading"]
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: header.frame.maxY + 40)).tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), "a tap on the page lowers the keyboard")
        XCTAssertEqual(prompt.value as? String, "a lighthouse", "the words stay")
        XCTAssertFalse(any("image.generating").exists, "nothing was generated")
        XCTAssertTrue(app.staticTexts["AI Image"].exists, "the sheet stays")
    }

    /// Cancel during a slow painting lets it go for good: it never lands.
    func testCancelDuringASlowGenerationDropsItForGood() {
        relaunch(["-GENERATE_DELAY", "3000"])
        generate("a lighthouse at dawn")
        XCTAssertTrue(any("image.generating").waitForExistence(timeout: 3))
        app.buttons["nav.leading"].tap()
        XCTAssertTrue(app.buttons["image.library.open"].waitForExistence(timeout: 5))
        app.buttons["image.source.generate"].tap()
        sleep(4)
        XCTAssertFalse(app.buttons["image.result.0"].exists, "a cancelled painting never shows up")
        XCTAssertEqual(photos.count, 0)
    }

    func testAFailedGenerationSaysSo() {
        generate("fail to paint this")
        XCTAssertTrue(app.staticTexts["image.notice"].waitForExistence(timeout: 8), "the failure is said")
        XCTAssertFalse(app.buttons["image.result.0"].exists)
        XCTAssertEqual(photos.count, 0)
    }

    func testOnePickOffersEditingAndLiftsIt() {
        openRecents()
        any("image.library.photo.3").tap()
        let editing = app.buttons["image.library.editing"]
        XCTAssertTrue(editing.waitForExistence(timeout: 3), "a single pick offers Editing (screen 26)")
        XCTAssertFalse(app.staticTexts["image.library.count"].exists)

        editing.tap()
        XCTAssertTrue(app.buttons["photo.filter.bw"].waitForExistence(timeout: 5), "the photo lifts into the editor")
        XCTAssertEqual(app.buttons["nav.leading"].label, "Cancel")
        XCTAssertEqual(app.buttons["nav.trailing"].label, "Done")
        XCTAssertEqual(photos.count, 1)

        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "Done returns to the page (F10A)")
        XCTAssertEqual(app.buttons["nav.trailing"].label, "Save")
        XCTAssertTrue(app.buttons["nav.trailing"].isEnabled)
        XCTAssertEqual(photos.count, 1)
    }
}
