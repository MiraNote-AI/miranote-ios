import XCTest

/// Full-screen writing (#184): the block being written opens on a page of
/// its own, and Done splits the words on every line break into one block
/// per line (blank lines dropped), top to bottom, as one undo step. Read
/// from the -UITEST probe.
final class FullScreenWritingUITests: XCTestCase {
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

    private var field: XCUIElement { app.descendants(matching: .any)["canvas.textEditor"] }
    private var page: XCUIElement { app.textViews["fullScreen.editor"] }
    private var entry: XCUIElement { app.buttons["text.fullScreen"] }

    private func startWriting(_ words: String) {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
    }

    /// Opens the page and replaces what it holds with `words`.
    private func writeFullScreen(_ words: String) {
        entry.tap()
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        let current = (page.value as? String) ?? ""
        page.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 1))
        page.typeText(words)
    }

    private func canvasState() -> [String: Any] {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let data = probe.label.data(using: .utf8) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// The page's text blocks, top to bottom: words, top, bottom, x, width.
    private func blocks() -> [(text: String, top: Double, bottom: Double, x: Double, w: Double)] {
        let elements = canvasState()["elements"] as? [[String: Any]] ?? []
        return elements.filter { $0["kind"] as? String == "text" }.map { element in
            let y = element["y"] as? Double ?? 0, h = element["h"] as? Double ?? 0
            return (element["text"] as? String ?? "", y - h / 2, y + h / 2,
                    element["x"] as? Double ?? 0, element["w"] as? Double ?? 0)
        }
        .sorted { $0.top < $1.top }
    }

    func testTheEntryShowsWhileWriting() {
        startWriting("draft")
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.isHittable, "over the keyboard, beside the dictation strip")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5), "only while words are written")
    }

    func testDoneWithThreeLinesGivesThreeBlocksTopToBottom() {
        startWriting("draft")
        writeFullScreen("first\nsecond, which is long enough to wrap onto more lines\n\n\nthird")
        app.buttons["fullScreen.done"].tap()
        XCTAssertTrue(page.waitForNonExistence(timeout: 5))
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "Done ends the writing")

        let stack = blocks()
        XCTAssertEqual(stack.map(\.text), ["first", "second, which is long en", "third"])
        for (upper, lower) in zip(stack, stack.dropFirst()) {
            XCTAssertGreaterThan(lower.top, upper.bottom, "no overlap")
            XCTAssertEqual(lower.x, upper.x, accuracy: 0.5, "same column")
            XCTAssertEqual(lower.w, upper.w, accuracy: 0.5)
        }
        XCTAssertGreaterThan(stack[1].bottom - stack[1].top, stack[2].bottom - stack[2].top,
                             "a wrapped line measures taller")
    }

    func testCancelChangesNothing() {
        startWriting("draft")
        writeFullScreen("first\n\nsecond")
        app.buttons["fullScreen.cancel"].tap()
        XCTAssertTrue(page.waitForNonExistence(timeout: 5))
        XCTAssertTrue(field.waitForExistence(timeout: 5), "still writing in place")
        XCTAssertEqual(field.value as? String, "draft")
        XCTAssertEqual(blocks().map(\.text), ["draft"])
        XCTAssertNotEqual(canvasState()["writing"] as? String, "", "the session goes on")
    }

    func testOneUndoRemovesTheSplit() {
        startWriting("draft")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        let before = canvasState()["undoDepth"] as? Int ?? 0

        // Done leaves the block selected: one tap writes again, and the
        // session's start keeps "draft".
        let words = app.staticTexts["draft"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        writeFullScreen("one\ntwo\nthree")
        app.buttons["fullScreen.done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertEqual(blocks().map(\.text), ["one", "two", "three"])
        XCTAssertEqual(canvasState()["undoDepth"] as? Int, before + 1, "the whole Done is one step")

        app.buttons["editor.undo"].tap()
        let back = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: words)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 5), .completed)
        XCTAssertEqual(blocks().map(\.text), ["draft"])
    }
}
