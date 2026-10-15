import XCTest

/// A tool open over the canvas acts on its own work only: with a photo
/// lifted, the header Undo -- like the floating one -- takes back this
/// visit's steps and never reaches under the scrim.
final class ToolScopeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Meng's #107 scenario through the header Undo: with the photo lifted
    /// and nothing edited in this visit, it must not take back the text
    /// block written before (hidden under the scrim, with no Redo).
    func testTheHeaderUndoWhileAPhotoIsLiftedLeavesANewerTextBlock() {
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        let photo = app.descendants(matching: .any).matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        app.buttons["nav.trailing"].tap()

        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Dinner with Mom")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.staticTexts["Dinner with Mom"].waitForExistence(timeout: 5))

        photo.press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["Edit photo"].waitForExistence(timeout: 5))
        app.buttons["Edit photo"].tap()
        XCTAssertTrue(app.buttons["photo.filter.bw"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["photo.undo"].isEnabled, "the floating Undo is scoped")
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled, "and so is the header's")

        app.buttons["editor.undo"].tap()
        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.staticTexts["Dinner with Mom"].waitForExistence(timeout: 3),
                      "the header Undo in the photo editor kept the text block under the scrim")
    }

    /// The header Undo takes back this visit's own edit, like the floating one.
    func testTheHeaderUndoWhileAPhotoIsLiftedTakesBackThisVisitsEdit() {
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        app.buttons["image.library.samples"].tap()
        let photo = app.descendants(matching: .any).matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        app.buttons["nav.trailing"].tap()

        photo.press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["Edit photo"].waitForExistence(timeout: 5))
        app.buttons["Edit photo"].tap()
        let bw = app.buttons["photo.filter.bw"]
        XCTAssertTrue(bw.waitForExistence(timeout: 5))
        bw.tap()
        XCTAssertTrue(bw.isSelected)
        XCTAssertTrue(app.buttons["editor.undo"].isEnabled)
        app.buttons["editor.undo"].tap()
        XCTAssertFalse(bw.isSelected, "the B&W came off")
        XCTAssertTrue(app.buttons["photo.filter.bw"].exists, "still editing the photo")
    }
}
