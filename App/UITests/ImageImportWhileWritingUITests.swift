import XCTest

/// #205 F10A: photos that land close the Image tool and the last one is
/// selected -- but a slow import landing while a block is being written
/// (the page stays live over the Recents sheet) leaves the writing alone:
/// the keyboard stays up and the words go on.
final class ImageImportWhileWritingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST", "-IMPORT_DELAY", "6000"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private var photos: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "element.image")
    }

    private var writing: String {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let state = (try? JSONSerialization.jsonObject(with: Data(probe.label.utf8))) as? [String: Any]
        return state?["writing"] as? String ?? ""
    }

    func testAnImportLandingWhileWritingKeepsTheWords() {
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Kettle")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["keyboard.done"].waitForNonExistence(timeout: 5))

        app.buttons["mode.image"].tap()
        let library = app.buttons["image.library.open"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        for index in 0..<2 {
            let cell = app.descendants(matching: .any).matching(identifier: "image.library.photo.\(index)").firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 5))
            cell.tap()
        }
        app.buttons["image.composer.add"].tap()

        // While the picks import, the block is opened again (select, then
        // a second tap) and written in.
        let block = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Kettle'")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        let frame = block.frame
        let spot = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        spot.tap()
        sleep(1)
        spot.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let session = writing
        XCTAssertFalse(session.isEmpty, "writing while the picks import")

        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: photos)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 12), .completed, "both picks landed")
        sleep(1)
        XCTAssertEqual(writing, session, "the landing left the writing alone")
        XCTAssertTrue(app.buttons["keyboard.done"].exists, "the keyboard stayed up")
        field.typeText(" song")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Kettle song'")).firstMatch
            .waitForExistence(timeout: 5), "the words went on")
        XCTAssertFalse(app.buttons["image.library.open"].exists, "the Image tool closed on the landing")
        XCTAssertFalse(app.buttons["mode.image"].isSelected)
    }
}
