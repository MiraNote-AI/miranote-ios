import XCTest

/// The chat composer as WeChat has it (owner decision). Sent photos last
/// as long as the chat, and go with it.
final class MiraChatComposerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Opens the chat from Home's quick field and waits for Mira's answer.
    private func openChat(_ arguments: [String] = []) {
        app.launchArguments = ["-UITEST"] + arguments
        app.launch()
        let quick = app.textFields["quick.field"]
        XCTAssertTrue(quick.waitForExistence(timeout: 8))
        quick.tap()
        quick.typeText("say hello")
        app.buttons["quick.send"].tap()
        XCTAssertTrue(app.buttons["chat.plus"].waitForExistence(timeout: 5))
        XCTAssertTrue(replies.firstMatch.waitForExistence(timeout: 8), "Mira answered")
    }

    private var replies: XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "scripted"))
    }

    /// A sent photo's file outlives the camera's full-screen cover (opened
    /// and closed again over the chat) and is deleted when the chat closes.
    func testASentPhotoOutlivesTheCameraCoverAndGoesWithTheChat() {
        openChat(["-CAMERA_COVER"])
        let files = app.staticTexts["debug.chatPhotoFiles"].firstMatch
        let staged = app.descendants(matching: .any)["chat.staged.0"]
        app.buttons["chat.plus"].tap()
        app.buttons["chat.tray.camera"].tap()
        XCTAssertTrue(app.buttons["camera.stub.use"].waitForExistence(timeout: 5), "the cover is up")
        app.buttons["camera.stub.use"].tap()
        XCTAssertTrue(staged.waitForExistence(timeout: 5))
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chat.message.photo"].waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == '1'"), evaluatedWith: files)
        waitForExpectations(timeout: 3)

        app.buttons["chat.plus"].tap()
        app.buttons["chat.tray.camera"].tap()
        XCTAssertTrue(app.buttons["camera.stub.use"].waitForExistence(timeout: 5), "the cover is up again")
        app.buttons["camera.stub.use"].tap()
        XCTAssertTrue(staged.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertEqual(files.label, "1", "the sent photo's file survived the cover")

        app.buttons["chat.home"].tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == '0'"), evaluatedWith: files)
        waitForExpectations(timeout: 3)
    }
}
