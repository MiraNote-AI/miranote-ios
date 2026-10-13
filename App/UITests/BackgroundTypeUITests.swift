import XCTest

/// Handoff screen 05: curated font sets restyle the page's text in one
/// undoable tap; one-tap layout waits for something to arrange.
final class BackgroundTypeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        app.buttons["Start a memory"].tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testAFontSetDressesThePageAndUndoTakesItOff() {
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("noodles by the bridge")
        app.buttons["keyboard.done"].tap()

        app.buttons["mode.background"].tap()
        let classic = app.buttons["background.fontSet.Classic"]
        XCTAssertTrue(classic.waitForExistence(timeout: 5))
        XCTAssertFalse(classic.isSelected)
        XCTAssertFalse(app.buttons["background.layout"].isEnabled, "one element has nothing to arrange")

        classic.tap()
        XCTAssertTrue(classic.isSelected, "the page now wears the set")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "font sets"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["Undo"].tap()
        XCTAssertFalse(classic.isSelected, "one undo takes the whole set off")
    }

    // The tile tapped is the tile chosen -- even on a page of body text
    // only, where sets once shared a face.
    func testOnlyTheTappedSetReadsAsChosen() {
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("a quiet afternoon")
        app.buttons["keyboard.done"].tap()

        app.buttons["mode.background"].tap()
        let soft = app.buttons["background.fontSet.Soft"]
        XCTAssertTrue(soft.waitForExistence(timeout: 5))
        soft.tap()
        XCTAssertTrue(soft.isSelected)
        for other in ["Classic", "Editorial", "Modern"] {
            XCTAssertFalse(app.buttons["background.fontSet.\(other)"].isSelected, "\(other) is not chosen")
        }
    }
}
