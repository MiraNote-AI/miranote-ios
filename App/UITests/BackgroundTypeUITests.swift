import XCTest

/// Handoff screen 05: a curated set dresses the page -- display and body
/// faces, text color and page color -- in one undoable tap; the Mira tidy
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

    private var probe: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
    }

    /// The page wears `hex` ("" for the default backdrop).
    private func pageColorIs(_ hex: String) -> Bool {
        let shows = NSPredicate(format: "label CONTAINS %@", "\"pageColor\":\"\(hex)\"")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shows, object: probe)],
                                timeout: 5) == .completed
    }

    // A set reads as chosen only while every title wears its face, every
    // block its color and the page its color -- so "selected" proves they
    // landed. Body text keeps its own face (R4A).
    func testACuratedSetDressesThePageAndUndoTakesItOff() {
        addText("noodles by the bridge")

        app.openBackground()
        XCTAssertFalse(app.buttons["background.tool.tidy"].isEnabled, "one element has nothing to arrange")
        app.openBackgroundRow("sets")
        let didot = app.buttons["background.set.didot-cardo"]
        XCTAssertTrue(didot.waitForExistence(timeout: 5))
        XCTAssertFalse(didot.isSelected)
        XCTAssertEqual(didot.frame.width, 44, accuracy: 0.5, "a full tap target")

        didot.tap()
        XCTAssertTrue(didot.isSelected, "the page now wears the set")
        XCTAssertTrue(pageColorIs("#FCD766"), "and its page color: \(probe.label)")
        XCTAssertTrue(probe.label.contains("\"font\":\"Josefin Sans\""), "body text keeps its face: \(probe.label)")
        XCTAssertFalse(probe.label.contains("\"font\":\"Didot\""), "no title here to re-font: \(probe.label)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "curated set"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["Undo"].tap()
        XCTAssertFalse(didot.isSelected, "one undo takes the whole set off")
        XCTAssertTrue(pageColorIs(""), "and the page color: \(probe.label)")
    }

    // The two Montserrat / Open Sans sets share their faces: the tile tapped
    // is the tile chosen, told apart by the page color.
    func testOnlyTheTappedSetReadsAsChosen() {
        addText("a quiet afternoon")

        app.openBackgroundRow("sets")
        let rose = app.buttons["background.set.montserrat-opensans-rose"]
        XCTAssertTrue(rose.waitForExistence(timeout: 5))
        rose.tap()
        XCTAssertTrue(rose.isSelected)
        XCTAssertFalse(app.buttons["background.set.montserrat-opensans"].isSelected, "the twin is not chosen")
        XCTAssertFalse(app.buttons["background.set.poppins-lora"].isSelected)
    }
}
