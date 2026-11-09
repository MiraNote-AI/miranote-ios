import XCTest

/// #184: words written on the canvas in paragraphs (blank lines between
/// them) become one block per paragraph when the writing ends -- Done or a
/// tap elsewhere, never Cancel -- top to bottom, as one undo step. A single
/// line break stays inside its block. Read from the -UITEST probe.
final class TextParagraphSplitUITests: XCTestCase {
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

    private func startWriting(_ words: String) {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
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

    /// The probe trims long words; waits out the end-of-writing split.
    private func waitForBlocks(_ count: Int) {
        let deadline = Date().addingTimeInterval(5)
        while blocks().count != count, Date() < deadline {
            _ = XCTWaiter().wait(for: [XCTestExpectation()], timeout: 0.2)
        }
    }

    func testDoneWithThreeParagraphsGivesThreeBlocksTopToBottom() {
        startWriting("first\n\nsecond, which is long enough to wrap onto more lines\n\n\nthird")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "Done ends the writing")
        waitForBlocks(3)

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

    func testATapOutsideAlsoSplits() {
        startWriting("one\n\ntwo")
        // Empty paper just above the block.
        let block = field.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: block.midX, dy: block.minY - 30)).tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "the tap ends the writing")
        waitForBlocks(2)
        XCTAssertEqual(blocks().map(\.text), ["one", "two"])
    }

    func testCancelDoesNotSplit() {
        startWriting("draft")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        let words = app.staticTexts["draft"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("\n\nmore")
        app.buttons["text.cancel"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "Cancel ends the writing")
        sleep(1)
        XCTAssertEqual(blocks().map(\.text), ["draft"], "the block as it was, in one piece")
    }

    func testASingleLineBreakStaysInsideOneBlock() {
        startWriting("a\nb")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        sleep(1)
        XCTAssertEqual(blocks().map(\.text), ["a\nb"])
    }

    func testOneUndoGivesBackTheSingleBlock() {
        startWriting("one\n\ntwo\n\nthree")
        let before = canvasState()["undoDepth"] as? Int ?? 0
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        waitForBlocks(3)
        XCTAssertEqual(blocks().map(\.text), ["one", "two", "three"])
        XCTAssertEqual(canvasState()["undoDepth"] as? Int, before + 1, "the split is one step")

        app.buttons["editor.undo"].tap()
        waitForBlocks(1)
        XCTAssertEqual(blocks().map(\.text), ["one\n\ntwo\n\nthree"], "one undo: the single block")
    }
}
