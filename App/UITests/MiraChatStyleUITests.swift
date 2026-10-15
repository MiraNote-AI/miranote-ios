import XCTest

/// Handoff screen 02 with the owner's WeChat-style composer: voice toggle on
/// the left, "+" on the right that becomes the Send pill once there is
/// something to send. Leaves by the Home pill.
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

    private func openChat() {
        let field = app.textFields["quick.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("say hello")
        app.buttons["quick.send"].tap()
        XCTAssertTrue(app.buttons["chat.plus"].waitForExistence(timeout: 5))
    }

    private var field: XCUIElement { app.descendants(matching: .any)["chat.field"] }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testChatSendsWithThePillAndLeavesByHome() {
        openChat()
        XCTAssertTrue(app.staticTexts["Ask Mira anything..."].exists)
        XCTAssertFalse(app.buttons["chat.send"].exists, "an empty draft offers +, not Send")
        attach("chat-empty")

        field.tap()
        field.typeText("one more thing")
        let send = app.buttons["chat.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertEqual(send.label, "Send")
        XCTAssertFalse(app.buttons["chat.plus"].exists, "+ became Send")
        attach("chat-typing")
        send.tap()
        XCTAssertTrue(app.staticTexts["one more thing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat.plus"].waitForExistence(timeout: 5), "Send went back to +")

        app.buttons["chat.home"].tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5))
    }

    // Voice-to-text: the transcript fills the field for editing; nothing
    // is sent on release.
    func testHoldToTalkFillsTheField() {
        openChat()
        app.buttons["chat.voice.toggle"].tap()
        let hold = app.descendants(matching: .any)["chat.voice.hold"]
        XCTAssertTrue(hold.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hold to talk"].exists)
        attach("chat-voice-mode")

        hold.press(forDuration: 1.5)

        XCTAssertTrue(field.waitForExistence(timeout: 5), "back in text mode after release")
        let filled = NSPredicate(format: "value CONTAINS %@", "Transcribed voice note (mock)")
        expectation(for: filled, evaluatedWith: field)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["chat.send"].exists, "the words wait for Send")
        XCTAssertFalse(app.staticTexts["Transcribed voice note (mock)"].exists, "not sent as a bubble")
        attach("chat-voice-filled")
    }

    func testSlidingUpCancelsTheClip() {
        openChat()
        app.buttons["chat.voice.toggle"].tap()
        let hold = app.descendants(matching: .any)["chat.voice.hold"]
        XCTAssertTrue(hold.waitForExistence(timeout: 5))

        let start = hold.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let away = start.withOffset(CGVector(dx: 0, dy: -140))
        start.press(forDuration: 0.8, thenDragTo: away)

        app.buttons["chat.voice.toggle"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ask Mira anything..."].exists, "a cancelled clip leaves the field empty")
        XCTAssertTrue(app.buttons["chat.plus"].exists)
    }

    func testPlusOpensThePhotoTray() {
        openChat()
        app.buttons["chat.plus"].tap()
        XCTAssertTrue(app.buttons["chat.tray.photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat.tray.camera"].exists)
        attach("chat-tray")

        app.buttons["chat.plus"].tap()
        XCTAssertFalse(app.buttons["chat.tray.photos"].waitForExistence(timeout: 2), "+ again closes it")
    }

    // Under -UITEST, Camera stages a canned photo (the system camera
    // cannot be driven) so the send path can run end to end.
    func testSendingAStagedPhotoShowsItInTheBubble() {
        openChat()
        app.buttons["chat.plus"].tap()
        app.buttons["chat.tray.camera"].tap()

        let staged = app.descendants(matching: .any)["chat.staged.0"]
        XCTAssertTrue(staged.waitForExistence(timeout: 5))
        let send = app.buttons["chat.send"]
        XCTAssertTrue(send.exists, "a photo alone can be sent")
        XCTAssertTrue(send.isEnabled)
        attach("chat-staged")

        field.tap()
        field.typeText("what should I write?")
        send.tap()

        XCTAssertTrue(app.descendants(matching: .any)["chat.message.photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["what should I write?"].exists)
        XCTAssertFalse(staged.exists, "the staged strip empties on send")
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "scripted")
        ).firstMatch.waitForExistence(timeout: 8), "Mira answered")
        attach("chat-photo-sent")
    }

    func testAStagedPhotoCanBeRemoved() {
        openChat()
        app.buttons["chat.plus"].tap()
        app.buttons["chat.tray.camera"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chat.staged.0"].waitForExistence(timeout: 5))

        app.buttons["chat.staged.0.remove"].tap()

        XCTAssertFalse(app.descendants(matching: .any)["chat.staged.0"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["chat.plus"].waitForExistence(timeout: 3), "nothing to send: Send went back to +")
    }
}
