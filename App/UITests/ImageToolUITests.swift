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
