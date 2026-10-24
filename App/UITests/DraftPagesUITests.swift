import XCTest

/// Save is the one way a page becomes saved (#137): Home keeps it as a
/// draft -- a toast says so and the journal cover is tagged -- except a
/// saved page left unchanged, which stays saved.
final class DraftPagesUITests: XCTestCase {
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

    private var draftToast: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "draft.toast").firstMatch
    }

    func testHomeKeepsANewPageAsADraft() {
        app.buttons["Start a memory"].tap()
        addTextBlock("picnic under the plane trees")
        app.buttons["Home"].tap()
        XCTAssertTrue(draftToast.waitForExistence(timeout: 5), "leaving says the page was kept as a draft")
        keepScreenshot("draft toast")

        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.picnic under the plane trees"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertEqual(cover.value as? String, "Draft")
        keepScreenshot("draft tag")
    }

    func testSaveTurnsADraftIntoASavedPage() {
        app.buttons["Start a memory"].tap()
        addTextBlock("picnic under the plane trees")
        app.buttons["Home"].tap()
        waitUntilGone(draftToast)
        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.picnic under the plane trees"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertEqual(cover.value as? String, "Draft")

        cover.tap()
        app.buttons["reading.edit"].tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        app.buttons["reading.back"].tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertNotEqual(cover.value as? String, "Draft")
    }

    func testChangingASavedPageWithoutSaveMakesItADraft() {
        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.Lunch by the river"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertNotEqual(cover.value as? String, "Draft", "seeded pages are saved")

        cover.tap()
        app.buttons["reading.edit"].tap()
        addTextBlock("and a second coffee")
        app.buttons["Home"].tap()
        XCTAssertTrue(draftToast.waitForExistence(timeout: 5))

        app.buttons["reading.back"].tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertEqual(cover.value as? String, "Draft")
    }

    // A guard: opening re-measures the page's text, which is no edit. (No
    // waiting on the toast NOT to show: a miss over the reading page took
    // XCUITest ten minutes to describe. The cover says it plainly.)
    func testLookingAtASavedPageKeepsItSaved() {
        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.Lunch by the river"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        cover.tap()
        app.buttons["reading.edit"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Home"].tap()

        app.buttons["reading.back"].tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertNotEqual(cover.value as? String, "Draft")
    }

    /// Adds a text block through the Text tool and closes the keyboard.
    private func addTextBlock(_ text: String) {
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text)
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }

    /// For the design review of the toast and the tag.
    private func keepScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func waitUntilGone(_ element: XCUIElement) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [gone], timeout: 5)
    }
}
