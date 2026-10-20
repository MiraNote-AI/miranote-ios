import XCTest

/// The Image tool in place over the canvas (handoff screens 23-26, 29):
/// Choose photos, the Recents grid with ordered picks, Add that stays in
/// Image mode, Cancel that takes the visit's photos back, and "Editing"
/// for a single pick. -UITEST reads nine painted samples instead of the
/// photo library.
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

    private var photos: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "element.image")
    }

    private func openRecents() {
        let library = app.buttons["image.library.open"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["nav.leading"].label, "Canvas")
        XCTAssertEqual(app.buttons["nav.trailing"].label, "Save")
        library.tap()
        XCTAssertTrue(any("image.library.photo.0").waitForExistence(timeout: 5))
    }

    func testPicksAreCountedInOrderAndAddStaysInImage() {
        openRecents()
        XCTAssertEqual(app.buttons["nav.leading"].label, "Cancel")
        XCTAssertEqual(app.buttons["nav.trailing"].label, "Add")
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
        XCTAssertFalse(any("image.library.grid").exists, "the sheet folds away")
        XCTAssertEqual(app.buttons["nav.trailing"].label, "Add", "still in Image mode (screen 25)")
        XCTAssertTrue(app.buttons["mode.image"].isSelected)

        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "Add keeps them and leaves")
        XCTAssertEqual(photos.count, 2)
    }

    /// A slow import (held 4 s): the header Add tapped twice lands the
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
        app.buttons["nav.trailing"].tap()
        XCTAssertFalse(app.buttons["nav.trailing"].isEnabled, "Add waits while the picks import")
        app.buttons["nav.trailing"].tap()
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

    func testCancelTakesThisVisitsPhotosBackInOneUndoableStep() {
        openRecents()
        any("image.library.photo.0").tap()
        any("image.library.photo.1").tap()
        app.buttons["nav.trailing"].tap()
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: photos)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 5), .completed)

        app.buttons["nav.leading"].tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5))
        XCTAssertEqual(photos.count, 0, "Cancel took them back")

        app.buttons["Undo"].tap()
        XCTAssertEqual(photos.count, 2, "one undo returns them")
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

        XCTAssertTrue(app.buttons["image.library.more"].exists, "share more photos with MiraNote")
        XCTAssertTrue(app.buttons["image.library.system"].exists, "or pick any photo once")
        XCTAssertTrue(any("image.library.photo.0").isHittable, "the shared photos are still the grid")
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
        XCTAssertEqual(app.buttons["nav.trailing"].label, "Add", "placed, as a library photo (screen 25)")

        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "Add keeps it and leaves")
        XCTAssertEqual(photos.count, 1)
        app.buttons["Undo"].tap()
        XCTAssertEqual(photos.count, 0, "one undo step takes it back")
    }

    func testCancelLetsTheCandidatesGo() {
        generate("a lighthouse at dawn")
        XCTAssertTrue(app.buttons["image.result.0"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["nav.leading"].label, "Cancel")
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

    /// The header Add while a painting waits: it says so and stays, the
    /// painting is not dropped.
    func testAddWhileAPaintingWaitsSaysSoAndStays() {
        relaunch(["-GENERATE_DELAY", "3000"])
        generate("a lighthouse at dawn")
        XCTAssertTrue(any("image.generating").waitForExistence(timeout: 3))
        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.staticTexts["image.notice"].waitForExistence(timeout: 3), "Add says why it waits")
        XCTAssertTrue(app.buttons["image.result.0"].waitForExistence(timeout: 8), "the painting still arrives")
        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.staticTexts["image.notice"].waitForExistence(timeout: 3), "a waiting pick holds Add too")
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
        app.buttons["nav.trailing"].tap()
        let photo = photos.firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["image.composer.add"].waitForExistence(timeout: 5),
                      "Done returns to Image mode with the photo placed (screen 29)")
        XCTAssertEqual(app.buttons["nav.trailing"].label, "Add")
    }
}
