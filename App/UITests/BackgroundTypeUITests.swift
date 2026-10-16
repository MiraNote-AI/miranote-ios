import XCTest

/// Handoff screen 05: a curated set dresses the page -- display and body
/// faces, text color and page color -- in one undoable tap; one-tap layout
/// waits for something to arrange.
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

    private func addText(_ words: String) {
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
        app.buttons["keyboard.done"].tap()
    }

    private var previewColor: String { app.staticTexts["background.preview.color"].label }

    // A set reads as chosen only while every text block wears its faces and
    // color and the page its color -- so "selected" proves all four landed.
    func testACuratedSetDressesThePageAndUndoTakesItOff() {
        addText("noodles by the bridge")

        app.buttons["mode.background"].tap()
        let didot = app.buttons["background.set.didot-cardo"]
        XCTAssertTrue(didot.waitForExistence(timeout: 5))
        XCTAssertFalse(didot.isSelected)
        XCTAssertFalse(app.buttons["background.layout"].isEnabled, "one element has nothing to arrange")

        didot.tap()
        XCTAssertTrue(didot.isSelected, "the page now wears the set")
        XCTAssertEqual(previewColor, "PREVIEW COLOR  \u{00B7}  #FCD766", "and its page color")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "curated set"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["Undo"].tap()
        XCTAssertFalse(didot.isSelected, "one undo takes the whole set off")
        XCTAssertEqual(previewColor, "PREVIEW COLOR  \u{00B7}  DEFAULT")
    }

    // The two Montserrat / Open Sans sets share their faces: the tile tapped
    // is the tile chosen, told apart by the page color.
    func testOnlyTheTappedSetReadsAsChosen() {
        addText("a quiet afternoon")

        app.buttons["mode.background"].tap()
        let rose = app.buttons["background.set.montserrat-opensans-rose"]
        XCTAssertTrue(rose.waitForExistence(timeout: 5))
        rose.tap()
        XCTAssertTrue(rose.isSelected)
        XCTAssertFalse(app.buttons["background.set.montserrat-opensans"].isSelected, "the twin is not chosen")
        XCTAssertFalse(app.buttons["background.set.poppins-lora"].isSelected)
    }
}
