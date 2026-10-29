import XCTest

/// Walks the text editor through the handoff's screens 10-21 in order and
/// photographs each state. The photos ride along as test attachments; with
/// SHOTS_DIR set (TEST_RUNNER_SHOTS_DIR for xcodebuild) they are also
/// written there, for the side-by-side review against the design.
final class TextEditorDesignShotsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Hold the Text tool's beat long enough to photograph screen 10.
        app.launchArguments = ["-UITEST", "-TEXT_MODE_BEAT", "2500"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? screenshot.pngRepresentation.write(
                to: URL(fileURLWithPath: directory).appendingPathComponent("app-\(name).png")
            )
        }
    }

    private func settle() {
        Thread.sleep(forTimeInterval: 0.8)
    }

    func testWalkThroughScreens10To21() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        XCTAssertTrue(app.buttons["text.cancel"].waitForExistence(timeout: 2), "the editing header")
        shot("10")

        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Sunny afternoon, there was a I walked into a noodle shop by the bridge.")
        XCTAssertTrue(app.buttons["style.font.Josefin"].isSelected, "Aa is open and Josefin is the face")
        settle()
        shot("11")

        app.buttons["style.colors"].tap()
        app.buttons["style.color.#F1EBDD"].tap()
        settle()
        shot("12")
        shot("13")

        app.buttons["style.color.custom"].tap()
        let hex = app.textFields["colorSheet.hex"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        replace(hex, with: "E5AC95")
        dismissHexKeyboard()
        settle()
        shot("14")

        // Pick color: the page under a loupe; a tap takes its color.
        app.buttons["colorSheet.pick"].tap()
        let page = app.descendants(matching: .any)["colorSheet.pick.page"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        shot("14-eyedropper")
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        XCTAssertNotEqual(hex.value as? String, "#E5AC95", "the sampled page color replaced the typed one")
        replace(hex, with: "E5AC95")
        dismissHexKeyboard()
        app.buttons["colorSheet.apply"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "the keyboard comes back")
        summonKeyboard(field)

        app.buttons["style.ai"].tap()
        app.buttons["style.ai.clean"].tap()
        settle()
        shot("15")

        let align = app.buttons["style.align"]
        align.tap()
        align.tap()
        align.tap()
        XCTAssertEqual(align.value as? String, "Left")
        settle()
        shot("16")
        align.tap()
        XCTAssertEqual(align.value as? String, "Centered")
        settle()
        shot("17")
        align.tap()
        align.tap()

        app.buttons["style.highlight"].tap()
        app.buttons["style.highlight.#171914"].tap()
        settle()
        shot("18")
        shot("19")

        app.buttons["style.highlight.custom"].tap()
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        replace(hex, with: "8B5962")
        dismissHexKeyboard()
        settle()
        shot("20")
        app.buttons["colorSheet.apply"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "the keyboard comes back")

        // Done leaves the block selected: the arrange state.
        app.buttons["keyboard.done"].tap()
        let block = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "noodle shop")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        settle()
        shot("21")
    }

    /// The simulator keeps the software keyboard down after a programmatic
    /// focus (it acts as if a hardware keyboard were attached) until
    /// something is typed: type a space and take it back.
    private func summonKeyboard(_ field: XCUIElement) {
        field.typeText(" " + XCUIKeyboardKey.delete.rawValue)
    }

    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 1))
        field.typeText(text)
    }

    /// The sheet's photographed state has no keyboard (screens 14, 20).
    private func dismissHexKeyboard() {
        app.textFields["colorSheet.hex"].typeText("\n")
    }
}
