import XCTest

/// Handoff screen 02: the chat leaves by the Home pill and sends with the
/// Send pill.
final class MiraChatStyleUITests: XCTestCase {
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

    func testChatSendsWithThePillAndLeavesByHome() {
        let field = app.textFields["quick.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("say hello")
        app.buttons["quick.send"].tap()

        let send = app.buttons["chat.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertEqual(send.label, "Send")
        XCTAssertTrue(app.staticTexts["Ask Mira anything..."].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "chat"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["chat.home"].tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5))
    }
}
