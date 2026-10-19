import XCTest

/// The owner's walk through every screen (owner, TestFlight 1.0(5): "open
/// every screen"): each step must land on its screen, and on each one no
/// tappable control may sit mostly under another one.
/// The photos ride along as attachments; with SHOTS_DIR set
/// (TEST_RUNNER_SHOTS_DIR for xcodebuild) they are also written there.
final class OwnerTourUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testEveryLibraryScreen() {
        check("home")

        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.Lunch by the river"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        check("journal")

        cover.tap()
        XCTAssertTrue(app.buttons["reading.share"].waitForExistence(timeout: 5))
        check("reading")
        app.buttons["reading.share"].tap()
        XCTAssertTrue(app.buttons["export.format.png"].waitForExistence(timeout: 5))
        check("export")
        app.buttons["reading.share"].tap()
        XCTAssertTrue(app.buttons["export.format.png"].waitForNonExistence(timeout: 5), "Share closes the sheet")

        app.buttons["reading.back"].tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5), "Back returns to the journal")
        app.buttons.matching(NSPredicate(format: "label == 'Home'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5), "Home returns home")
    }

    func testChat() {
        let field = app.textFields["quick.field"]
        field.tap()
        field.typeText("noodle shop")
        app.buttons["quick.send"].tap()
        XCTAssertTrue(app.buttons["chat.hit.Lunch by the river"].waitForExistence(timeout: 8))
        check("chat")
        app.buttons["chat.home"].tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5), "the chat's Home pill goes home")
    }

    func testEveryCanvasTool() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        check("canvas")

        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("A long walk by the water")
        check("text")
        app.buttons["keyboard.done"].tap()

        app.buttons["mode.image"].tap()
        XCTAssertTrue(app.buttons["image.library.samples"].waitForExistence(timeout: 5))
        check("image")
        app.buttons["image.library.samples"].tap()
        let photo = app.descendants(matching: .any).matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        app.buttons["nav.trailing"].tap()

        photo.press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["Edit photo"].waitForExistence(timeout: 5))
        app.buttons["Edit photo"].tap()
        XCTAssertTrue(app.buttons["photo.filter.bw"].waitForExistence(timeout: 5))
        check("photo-edit")
        app.buttons["nav.trailing"].tap()

        open("mode.background", until: app.descendants(matching: .any)["background.title"])
        check("background")
        // A tool's header: "Canvas" leads back; the trailing Save files the page.
        app.buttons["nav.leading"].tap()

        open("mode.sticker", until: app.buttons["sticker.tab.make"])
        check("sticker")
        app.buttons["nav.leading"].tap()

        // Voice is a strip on the canvas itself; its X lets it go.
        open("mode.voice", until: app.buttons["recorder.cancel"])
        check("voice")
        app.buttons["recorder.cancel"].tap()
        XCTAssertTrue(app.buttons["recorder.cancel"].waitForNonExistence(timeout: 5), "the X closes the strip")

        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5), "back on the canvas")
        check("canvas-filled")
    }

    private func open(_ tool: String, until element: XCUIElement) {
        let button = app.buttons[tool]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(tool) opened nothing")
    }

    /// Photographs the screen and checks that no tappable control on it is
    /// mostly under another one.
    private func check(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? screenshot.pngRepresentation.write(
                to: URL(fileURLWithPath: directory).appendingPathComponent("tour-\(name).png")
            )
        }

        // Controls scrolled out of a strip or a list are clipped on purpose:
        // only the ones fully on screen count.
        let window = app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1)
        let controls = app.buttons.allElementsBoundByIndex
            .filter { $0.exists && !$0.frame.isEmpty && window.contains($0.frame) && $0.isHittable }
            .map { (name: $0.identifier.isEmpty ? $0.label : $0.identifier, frame: $0.frame) }
        XCTAssertFalse(controls.isEmpty, "\(name): nothing to tap")
        for (index, first) in controls.enumerated() {
            for second in controls[(index + 1)...] {
                let shared = first.frame.intersection(second.frame)
                guard !shared.isNull else { continue }
                let smaller = min(first.frame.width * first.frame.height, second.frame.width * second.frame.height)
                XCTAssertLessThan(shared.width * shared.height, smaller * 0.5,
                                  "\(name): \(first.name) and \(second.name) cover each other")
            }
        }
    }
}
