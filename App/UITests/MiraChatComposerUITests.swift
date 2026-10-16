import XCTest

/// The chat composer as WeChat has it (owner decision): the field grows with
/// the message, the keyboard's Send sends and the keyboard stays up for the
/// next one, a paste never sends (MiraChatStyleUITests). Sent photos last
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

    private var field: XCUIElement { app.descendants(matching: .any)["chat.field"] }

    private var replies: XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "scripted"))
    }

    private var hasKeyboardFocus: Bool { (field.value(forKey: "hasKeyboardFocus") as? Bool) == true }

    func testReturnSendsAndTheKeyboardStaysUp() {
        openChat()
        field.tap()
        field.typeText("first message\n")
        XCTAssertTrue(app.staticTexts["first message"].waitForExistence(timeout: 5), "Return sent it")
        let answered = NSPredicate(format: "count == 2")
        expectation(for: answered, evaluatedWith: replies)
        waitForExpectations(timeout: 8)

        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard stays up after Send")
        XCTAssertTrue(hasKeyboardFocus, "the field keeps the keyboard")
        // The next message is typed straight away, without a tap.
        app.typeText("second message\n")
        XCTAssertTrue(app.staticTexts["second message"].waitForExistence(timeout: 5), "the next one went too")
    }

    func testALongMessageWrapsAndTheFieldGrows() {
        openChat()
        field.tap()
        let oneLine = field.frame.height
        field.typeText("a long message that keeps going well past the width of the field")
        XCTAssertGreaterThan(field.frame.height, oneLine + 8, "the field grows to show the next line")

        field.typeText(String(repeating: " and on and on", count: 20))
        let capped = field.frame.height
        XCTAssertGreaterThan(capped, oneLine + 8)
        XCTAssertLessThan(capped, oneLine * 3, "four lines at most, then it scrolls")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "a long message")).count, 0,
                       "nothing was sent")
    }

    /// The quick starts send their label straight away: while Mira answers
    /// they are disabled, not silently ignored.
    func testQuickStartsWaitWhileMiraAnswers() {
        openChat()
        field.tap()
        field.typeText("tell me slowly\n")
        let chip = app.buttons["chat.quick.Rewrite softer"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        let waiting = NSPredicate(format: "isEnabled == false")
        expectation(for: waiting, evaluatedWith: chip)
        waitForExpectations(timeout: 3)
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
