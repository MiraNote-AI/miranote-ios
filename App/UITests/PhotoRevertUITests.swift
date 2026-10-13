import XCTest

/// Handoff screens 27-28: once a photo is edited, the panel offers a held
/// compare and a one-step revert to how it was when editing began.
final class PhotoRevertUITests: XCTestCase {
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

    func testRevertPutsThePhotoBackAndUndoReturnsTheEdit() {
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

        let revert = app.buttons["photo.revert"]
        XCTAssertTrue(app.buttons["photo.filter.bw"].waitForExistence(timeout: 5))
        XCTAssertFalse(revert.exists, "nothing to revert before an edit")

        app.buttons["photo.filter.bw"].tap()
        XCTAssertTrue(revert.waitForExistence(timeout: 3))
        let compare = app.descendants(matching: .any).matching(identifier: "photo.compare").firstMatch
        XCTAssertTrue(compare.exists)
        compare.press(forDuration: 0.6)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "photo.before").firstMatch.exists,
                       "letting go shows the edit again")

        revert.tap()
        XCTAssertTrue(app.buttons["photo.filter.none"].isSelected, "back to the original look")
        XCTAssertFalse(revert.exists)

        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["photo.filter.bw"].waitForExistence(timeout: 3))
        XCTAssertTrue(revert.waitForExistence(timeout: 3), "one undo brings the edit back")
    }
}
