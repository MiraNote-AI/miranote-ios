import XCTest

/// The text session's edges (review of #105): header undo with the custom
/// color sheet up, the custom background's Apply, and the dictation strip
/// beside a live voice take; on a reopened block, one Undo per change made
/// through the AI row (#252).
final class TextSessionUITests: XCTestCase {
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

    private func tapText(_ words: String) {
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
    }

    func testHeaderUndoWithTheColorSheetUpOnlyDropsThePreview() {
        app.buttons["Start a memory"].tap()
        tapText("restyle me")
        app.openTextRow("style.font")
        app.buttons["style.font.Futura"].tap()
        XCTAssertTrue(app.buttons["style.font.Futura"].isSelected)

        app.openTextRow("style.colors")
        app.buttons["style.color.custom"].tap()
        let hex = app.textFields["colorSheet.hex"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        hex.tap()
        let current = (hex.value as? String) ?? ""
        hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 1))
        hex.typeText("112233\n")

        app.buttons["editor.undo"].tap()
        XCTAssertTrue(app.buttons["colorSheet.apply"].waitForNonExistence(timeout: 5), "undo closes the sheet")
        app.openTextRow("style.font")
        XCTAssertTrue(app.buttons["style.font.Futura"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["style.font.Futura"].isSelected, "the font step before the preview stays")
        XCTAssertTrue(field.exists, "and so does the block")
    }

    func testCustomBackgroundApplyKeepsTheShownColor() {
        app.buttons["Start a memory"].tap()
        tapText("on plum")
        app.openTextRow("style.highlight")
        app.buttons["style.highlight.custom"].tap()
        let apply = app.buttons["colorSheet.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5))

        let custom = app.buttons["style.highlight.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        XCTAssertTrue(custom.isSelected, "the color the sheet showed is the block's background")
        XCTAssertFalse(app.buttons["style.highlight.none"].isSelected)
    }

    func testTheStripNeverTakesOverAVoiceTake() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.voice"].waitForExistence(timeout: 5))
        app.buttons["mode.voice"].tap()
        app.buttons["recorder.record"].tap()
        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 5))

        tapText("caption")
        app.buttons["style.mic"].tap()
        // Give a wrongly started transcription time to land.
        let dictated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "Transcribed"), object: field
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dictated], timeout: 3), .timedOut,
                       "the voice take is not dictated into the block")
        XCTAssertEqual(field.value as? String, "caption")

        app.buttons["keyboard.done"].tap()
        let stop = app.buttons["recorder.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        XCTAssertTrue(app.buttons["recorder.keep"].waitForExistence(timeout: 5), "Stop still ends the take")
    }

    /// #252: on a reopened block, a size and then a rewrite kept from the
    /// AI row are two changes and two Undos. Before, the rewrite's first
    /// words and its keeping each recorded the page under it, so the second
    /// Undo did nothing and the size needed a third.
    func testASizeThenAKeptRewriteOnAReopenedBlockUndoOnceEach() {
        let depth = reopenAndSize("noodle shop")
        app.openTextRow("style.ai")
        app.buttons["style.ai.expand"].tap()
        XCTAssertTrue(waitForField("CONTAINS", "(expanded draft -- mock)"), "the version shows")
        app.backToTextRow()
        XCTAssertEqual(settledProbe()["undoDepth"] as? Int, depth + 2, "the size and the rewrite")

        app.buttons["editor.undo"].tap()
        XCTAssertTrue(waitForField("==", "noodle shop"), "the first Undo takes the rewrite back")
        XCTAssertEqual(pointSize(), 30, "and leaves the size")
        app.buttons["editor.undo"].tap()
        XCTAssertEqual(pointSize(), 21, "the second takes the size back")
    }

    /// #252: a version shown, then Original picked again, leaves no step:
    /// the next Undo takes back the size.
    func testAVersionTakenBackOnAReopenedBlockLeavesNoUndo() {
        let depth = reopenAndSize("noodle shop")
        app.openTextRow("style.ai")
        app.buttons["style.ai.expand"].tap()
        XCTAssertTrue(waitForField("CONTAINS", "(expanded draft -- mock)"), "the version shows")
        app.buttons["style.ai.original"].tap()
        XCTAssertTrue(waitForField("==", "noodle shop"), "Original brings the words back")
        app.backToTextRow()
        XCTAssertEqual(settledProbe()["undoDepth"] as? Int, depth + 1, "only the size")

        app.buttons["editor.undo"].tap()
        XCTAssertEqual(pointSize(), 21, "the first Undo takes the size back")
    }

    /// A new block holding `words`, written and ended, opened again with a
    /// tap and set to L: the undo depth before the size.
    private func reopenAndSize(_ words: String) -> Int {
        app.buttons["Start a memory"].tap()
        tapText(words)
        app.buttons["keyboard.done"].tap()
        let block = app.staticTexts[words]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        // Done leaves the block selected: one tap writes again.
        block.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let depth = settledProbe()["undoDepth"] as? Int ?? -1
        app.openTextRow("style.size")
        app.buttons["style.size.L"].tap()
        XCTAssertEqual(pointSize(), 30, "L")
        return depth
    }

    private func waitForField(_ comparison: String, _ words: String) -> Bool {
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value \(comparison) %@", words), object: field
        )
        return XCTWaiter.wait(for: [shown], timeout: 5) == .completed
    }

    /// The -UITEST probe once it has caught up (it refreshes every 0.25 s).
    private func settledProbe() -> [String: Any] {
        XCTAssertTrue(app.canvasProbe.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)
        return (try? JSONSerialization.jsonObject(with: Data(app.canvasProbe.label.utf8)) as? [String: Any]) ?? [:]
    }

    /// The point size of the page's one text block.
    private func pointSize() -> Double? {
        let texts = (settledProbe()["elements"] as? [[String: Any]] ?? []).filter { $0["kind"] as? String == "text" }
        XCTAssertEqual(texts.count, 1, "one text block on the page")
        return texts.first?["pointSize"] as? Double
    }
}
