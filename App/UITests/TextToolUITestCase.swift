import XCTest

/// A canvas open on an empty page, and the -UITEST probe's `textOpen`
/// entry, for the Text tool's open tests (#162).
class TextToolUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func canvasState() -> [String: Any] {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let data = probe.label.data(using: .utf8) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// The probe's `textOpen` once `opens` has reached `count` (it refreshes
    /// every 0.25 s).
    func textOpen(after count: Int) -> [String: Any] {
        let deadline = Date().addingTimeInterval(5)
        var last: [String: Any] = [:]
        while Date() < deadline {
            last = canvasState()["textOpen"] as? [String: Any] ?? [:]
            if (last["opens"] as? Int ?? 0) >= count { return last }
            usleep(100_000)
        }
        XCTFail("textOpen never reached \(count) opens: \(last)")
        return last
    }

    /// Taps Text and waits for the app to hear the software keyboard rise;
    /// skips the test when none does (a hardware keyboard is connected;
    /// XCUITest still finds a keyboard then, parked below the screen).
    func openText() throws {
        app.buttons["mode.text"].tap()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if (canvasState()["textOpen"] as? [String: Any])?["keyboardShows"] as? Int ?? 0 >= 1 { return }
            usleep(100_000)
        }
        throw XCTSkip("hardware keyboard connected: no software keyboard to time")
    }

    func cancelText() {
        app.buttons["text.cancel"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    func write(_ words: String) {
        app.buttons["mode.text"].tap()
        let field = any("canvas.textEditor")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }
}
