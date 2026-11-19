import XCTest

/// #205 PR 4: one row in the text slot at a time. Each tool's row takes
/// the text row's place with its own Back, the keyboard stays up, and the
/// rows apply as decided: Size on a tap (K2A), fonts on a settle (R6B).
final class TextSlotUITests: TextToolUITestCase {
    private var field: XCUIElement { any("canvas.textEditor") }

    private func startWriting(_ words: String) {
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
    }

    /// The block being written, as the probe reads it.
    private func block() -> [String: Any] {
        let texts = (canvasState()["elements"] as? [[String: Any]] ?? []).filter { $0["kind"] as? String == "text" }
        return texts.first ?? [:]
    }

    private func undoDepth() -> Int { canvasState()["undoDepth"] as? Int ?? -1 }

    /// Waits for the probe (refreshed every 0.25 s) to show `value` at `key`.
    private func waitForBlock(_ key: String, _ value: String, _ message: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        // Sizes come as numbers: read 21 as "21.0".
        func read() -> String {
            let raw = block()[key]
            return (raw as? Double).map { "\($0)" } ?? "\(raw ?? "-")"
        }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if read() == value { return }
            usleep(150_000)
        }
        XCTFail("\(message): \(key) is \(read()), not \(value)", file: file, line: line)
    }

    /// The slot's one row, once a level change has settled.
    private func assertOneRow(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(any(identifier).waitForExistence(timeout: 3), "\(identifier) shows", file: file, line: line)
        // The leaving row fades for about 0.22 s.
        usleep(600_000)
        let rows = app.textSlotRows.allElementsBoundByIndex.map(\.identifier)
        XCTAssertEqual(rows, [identifier], "one row in the text slot", file: file, line: line)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard stays up (Q4A)", file: file, line: line)
        XCTAssertTrue(any("style.mic").exists, "the chat box stays below the row", file: file, line: line)
    }

    func testOnlyOneTextSlotRowAtATime() {
        startWriting("one row")
        assertOneRow("text.row.tools")
        let slot = any("text.row.tools").frame
        let rows = [("style.font", "text.row.font", "style.font.Josefin"),
                    ("style.size", "text.row.size", "style.size.M"),
                    ("style.colors", "text.row.color", "style.color.custom"),
                    ("style.ai", "text.row.ai", "style.ai.original"),
                    ("style.highlight", "text.row.background", "style.highlight.none")]
        for (tool, row, cell) in rows {
            app.openTextRow(tool)
            assertOneRow(row)
            let frame = any(row).frame
            XCTAssertEqual(frame.minY, slot.minY, accuracy: 0.5, "\(row) sits where the text row was")
            XCTAssertEqual(frame.height, slot.height, accuracy: 0.5, "\(row) is as tall: the page never moves")
            XCTAssertTrue(app.buttons[cell].exists, "\(row) shows its own cells")
            XCTAssertFalse(app.buttons["keyboard.done"].exists, "\(row): the text row is gone, not under it")
            for other in ["style.font", "style.size", "style.colors", "style.ai", "style.align"] {
                XCTAssertFalse(app.buttons[other].exists, "\(row): \(other) is not stacked with it")
            }
            app.backToTextRow()
            assertOneRow("text.row.tools")
        }
        XCTAssertEqual(block()["text"] as? String, "one row", "still writing the same words")
    }

    func testSizeRowSetsFifteenTwentyOneThirty() {
        startWriting("sizes")
        app.openTextRow("style.size")
        XCTAssertTrue(app.buttons["style.size.M"].isSelected, "a new block is M")
        waitForBlock("pointSize", "21.0", "a new block")
        for (size, points) in [("S", "15.0"), ("L", "30.0"), ("M", "21.0")] {
            let before = undoDepth()
            app.buttons["style.size.\(size)"].tap()
            waitForBlock("pointSize", points, "\(size) applies on the tap")
            XCTAssertTrue(app.buttons["style.size.\(size)"].isSelected)
            XCTAssertEqual(undoDepth(), before + 1, "\(size) is one undo step")
        }
        app.buttons["editor.undo"].tap()
        waitForBlock("pointSize", "30.0", "undo takes the last size back")
        XCTAssertTrue(app.buttons["style.size.L"].isSelected)

        let before = undoDepth()
        app.buttons["style.size.L"].tap()
        sleep(1)
        XCTAssertEqual(undoDepth(), before, "the size already set adds no step")
    }

    /// The font row opens on the block's face without applying; a swipe
    /// that comes to rest applies the face under the marker as one step,
    /// and Undo scrolls the row back without applying again (G24).
    func testFontRowAppliesOnSettleAsOneStep() {
        startWriting("snap")
        let before = undoDepth()
        app.openTextRow("style.font")
        let josefin = app.buttons["style.font.Josefin"]
        XCTAssertTrue(josefin.waitForExistence(timeout: 3))
        XCTAssertTrue(josefin.isSelected)
        sleep(1)
        XCTAssertEqual(undoDepth(), before, "opening the row applies nothing")

        // One chip (65 + 6) to the left, slowly, so it settles on the next.
        let start = josefin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -71, dy: 0)),
                    withVelocity: 80, thenHoldForDuration: 0.3)
        waitForBlock("font", "Optima", "the face under the marker applies")
        XCTAssertTrue(app.buttons["style.font.Optima"].isSelected)
        XCTAssertEqual(undoDepth(), before + 1, "one undo step for the settle")

        app.buttons["editor.undo"].tap()
        waitForBlock("font", "Josefin Sans", "undo takes the face back")
        sleep(1)
        XCTAssertTrue(josefin.isSelected, "the row follows the undo")
        XCTAssertEqual(block()["font"] as? String, "Josefin Sans", "and scrolling back applied nothing")
    }

    /// The color row is a snap row too (P7A): a tapped dot applies.
    func testColorAndHighlightDotsApply() {
        startWriting("dots")
        app.openTextRow("style.colors")
        app.buttons["style.color.#9B7A70"].tap()
        waitForBlock("color", "#9B7A70", "a tapped color applies")
        app.openTextRow("style.highlight")
        app.buttons["style.highlight.#B4826D"].tap()
        waitForBlock("fill", "#B4826D", "a tapped fill applies")
        app.buttons["style.highlight.none"].tap()
        waitForBlock("fill", "", "none takes it off")
    }

    /// Where the snap row's marker is: the middle of the row past its Back
    /// (36 wide, 8 before the row).
    private func markerX(_ row: String) -> CGFloat {
        let frame = any(row).frame
        return (frame.minX + 36 + 8 + frame.maxX) / 2
    }

    /// A new block's ink has no dot of its own: the color row opens on the
    /// first dot, unselected, and applies nothing; Undo after a pick scrolls
    /// it back there, again applying nothing (G24).
    func testColorRowOpensAndUndoesWithoutApplying() {
        startWriting("ink")
        let before = undoDepth()
        app.openTextRow("style.colors")
        let forest = app.buttons["style.color.#24382D"]
        XCTAssertTrue(forest.waitForExistence(timeout: 3))
        sleep(1)
        XCTAssertEqual(undoDepth(), before, "opening the row applies nothing")
        XCTAssertEqual(block()["color"] as? String, "#293322")
        XCTAssertFalse(forest.isSelected, "the ink is not Forest")

        app.buttons["style.color.#8B5662"].tap()
        waitForBlock("color", "#8B5662", "a tapped dot applies")
        app.buttons["editor.undo"].tap()
        waitForBlock("color", "#293322", "undo takes it back")
        sleep(1)
        XCTAssertEqual(block()["color"] as? String, "#293322", "scrolling back applied nothing")
        XCTAssertEqual(undoDepth(), before, "and recorded nothing")
        XCTAssertEqual(forest.frame.midX, markerX("text.row.color"), accuracy: 2, "the row went back to its start")
    }

    /// Custom is an action: coming to rest on it applies nothing and opens
    /// no sheet.
    func testSettlingOnCustomAppliesNothing() {
        startWriting("custom")
        app.openTextRow("style.colors")
        let before = undoDepth()
        // A fling from the row's right side carries it to its end.
        let forest = app.buttons["style.color.#24382D"].frame
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: markerX("text.row.color") + 140, dy: forest.midY))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -240, dy: 0)),
                    withVelocity: 3000, thenHoldForDuration: 0)
        sleep(1)
        let custom = app.buttons["style.color.custom"]
        XCTAssertEqual(custom.frame.midX, markerX("text.row.color"), accuracy: 2,
                       "Custom came to rest under the marker")
        XCTAssertEqual(undoDepth(), before, "nothing applied")
        XCTAssertEqual(block()["color"] as? String, "#293322")
        XCTAssertFalse(app.buttons["colorSheet.apply"].exists, "no sheet")
    }
}
