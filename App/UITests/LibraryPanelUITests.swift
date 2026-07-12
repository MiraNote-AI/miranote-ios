import XCTest

/// UI tests for the fourth toolbar slot: the shared library folder of
/// saved stickers and images (issue #30).
final class LibraryPanelUITests: XCTestCase {
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

    // The bar has a fourth slot, and a fresh profile opens to the empty
    // state that explains how items get here.
    func testLibraryButtonOpensEmptyFolder() {
        app.buttons["Start a memory"].tap()
        let library = app.buttons["mode.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5), "fourth toolbar slot")
        library.tap()

        XCTAssertTrue(app.staticTexts["library.empty"].waitForExistence(timeout: 5),
                      "empty folder explains itself")
    }

    // The bookmark on the photo edit panel files the photo; the library
    // panel lists it; a tap places it back on the canvas as an image.
    func testSavePhotoThenPlaceFromLibrary() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()

        let photo = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        let photosBefore = app.descendants(matching: .any)
            .matching(identifier: "element.image").count

        photo.press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["Edit photo"].waitForExistence(timeout: 5))
        app.buttons["Edit photo"].tap()

        let save = app.buttons["photo.saveToLibrary"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["Saved to your library."].waitForExistence(timeout: 5))

        // Saving twice files it once.
        save.tap()
        XCTAssertTrue(app.staticTexts["Already in your library."].waitForExistence(timeout: 5))
        app.buttons["photo.done"].tap()

        // Into the folder; the saved photo is there; tap places it.
        let library = app.buttons["mode.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        let item = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "library.item.")
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the saved photo lists in the folder")
        item.tap()

        // Back on the canvas with one more image element than before.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        let photosAfter = app.descendants(matching: .any)
            .matching(identifier: "element.image").count
        XCTAssertEqual(photosAfter, photosBefore + 1,
                       "the library places the photo as an image element")
    }

    // A generated sticker (which already lands in the folder) places from
    // the library as a sticker element, not an image.
    func testGeneratedStickerPlacesFromLibraryAsSticker() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()

        app.buttons["image.source.generate"].tap()
        let stickerStyle = app.buttons["image.style.sticker"]
        XCTAssertTrue(stickerStyle.waitForExistence(timeout: 5))
        stickerStyle.tap()
        let prompt = app.textFields["image.prompt"]
        prompt.tap()
        prompt.typeText("a paper crane")
        app.buttons["image.generate.run"].tap()

        let result = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "image.result.")
        ).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()

        let stickersBefore = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").count

        let library = app.buttons["mode.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        let item = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "library.item.")
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()

        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        let stickersAfter = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").count
        XCTAssertEqual(stickersAfter, stickersBefore + 1,
                       "the library places a saved sticker as a sticker element")
    }
}
