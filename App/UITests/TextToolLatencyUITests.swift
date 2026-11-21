import XCTest

/// #162: a tap on Text brings the keyboard and the text tools up at once,
/// with no stall (the settled screen: `TextToolLayoutUITests`). Times
/// come from the -UITEST probe's `textOpen` entry (tap -> keyboardDidShow,
/// measured in the app, not by the test runner).
final class TextToolLatencyUITests: TextToolUITestCase {
    private static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: Latency

    /// One cold open, then four warm ones: each times the tap to the
    /// keyboard landing, with the tools mounted on the way.
    func testTextToolOpenLatency() throws {
        var rows: [[String: Any]] = []
        for open in 1...5 {
            let bodiesBefore = canvasState()["sceneBodies"] as? Int ?? 0
            try openText()
            var row = textOpen(after: open)
            row["sceneBodies"] = (canvasState()["sceneBodies"] as? Int ?? 0) - bodiesBefore
            XCTAssertGreaterThan(row["keyboardMs"] as? Int ?? -1, 0, "open \(open): \(row)")
            XCTAssertGreaterThanOrEqual(row["keyboardShows"] as? Int ?? 0, 1, "open \(open): \(row)")
            XCTAssertGreaterThanOrEqual(row["accessoryMs"] as? Int ?? -1, 0, "open \(open): \(row)")
            rows.append(row)
            leaveText()
        }
        let warm = rows.dropFirst().map { $0["ms"] as? Int ?? -1 }
        let line = "text-open-ms cold=\(rows[0]) warm=\(Array(rows.dropFirst())) warmMedian=\(Self.median(warm))"
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "text-open-ms"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThanOrEqual(Self.median(warm), Self.warmCeilingMs, line)
    }

    /// Warm opens on iPhone 17 simulators: a median 903 ms before the fix
    /// (the 250 ms Text beat, then the keyboard), 620 after. The ceiling is
    /// halfway, rounded up to 50: a just-booted simulator ran 757, the beat
    /// put back runs 919.
    private static let warmCeilingMs = 800

    /// The tools come up with the keyboard, not before it: they show the
    /// frame the keyboard starts to rise and ride up on it (they used to
    /// sit over the tool bar for ~120 ms first, then jump up).
    func testToolsAppearWithTheKeyboard() throws {
        for open in 1...3 {
            try openText()
            let row = textOpen(after: open)
            let shown = row["toolsVisibleMs"] as? Int ?? -1, rise = row["willShowMs"] as? Int ?? -1
            XCTAssertGreaterThanOrEqual(rise, 0, "open \(open): no keyboard rise heard: \(row)")
            XCTAssertGreaterThanOrEqual(shown, rise - 20, "open \(open): tools before the keyboard: \(row)")
            XCTAssertLessThanOrEqual(shown, rise + 40, "open \(open): tools after the keyboard: \(row)")
            leaveText()
        }
    }

    /// No keyboard rise heard (as with a hardware keyboard): the tools still
    /// show, a moment after the field takes focus, and can be used.
    func testToolsShowWhenNoKeyboardRises() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-NO_KEYBOARD_SIGNAL"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let deadline = Date().addingTimeInterval(5)
        var row: [String: Any] = [:]
        while Date() < deadline {
            row = canvasState()["textOpen"] as? [String: Any] ?? [:]
            if (row["toolsVisibleMs"] as? Int ?? -1) >= 0 { break }
            usleep(100_000)
        }
        let shown = row["toolsVisibleMs"] as? Int ?? -1, focus = row["focusMs"] as? Int ?? -1
        XCTAssertGreaterThanOrEqual(shown, 0, "tools never showed: \(row)")
        // Not after the whole 1.5 s wait for a keyboard (the stall of #162).
        XCTAssertLessThan(shown - focus, 600, "the tools showed \(shown - focus) ms after focus: \(row)")
        // And they work: a tap on a font sets it.
        app.openTextRow("style.font")
        let futura = app.buttons["style.font.Futura"]
        futura.tap()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: futura)
        waitForExpectations(timeout: 3)
    }

    /// The wait for a keyboard that never comes belongs to one open: an
    /// earlier open's wait, run out, never shows the next open's tools
    /// ahead of its own keyboard (#162's pop, back again).
    func testAnEarlierOpensWaitLeavesTheNextOpenAlone() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-NO_KEYBOARD_SIGNAL", "-LONG_TOOLS_WAIT"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        write("kept")
        let block = app.staticTexts["kept"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        // One open and out, then the next as soon as the keyboard is down.
        block.tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        if !field.waitForExistence(timeout: 2) { block.tap() }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Out before the tools (and their Back) show: a tap on the bare page.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 200, dy: 160)).tap()
        let down = NSPredicate(format: "exists == false")
        expectation(for: down, evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
        // The page tap let go of the block: one tap selects it again, the
        // timed one opens it.
        block.tap()
        let start = Date()
        block.tap()
        var shownAfter = -1.0
        while Date().timeIntervalSince(start) < 7 {
            if canvasState()["textToolsShown"] as? Bool == true {
                shownAfter = Date().timeIntervalSince(start)
                break
            }
            usleep(50_000)
        }
        // The wait is 4 s here; the earlier open's runs out ~3 s sooner.
        XCTAssertGreaterThan(shownAfter, 3.0, "the tools showed \(shownAfter) s into the open")
    }

    /// A tap on the font row, even between two chips, stays in the session
    /// and sets the font (a tap through the rising row's gaps used to fall
    /// to the page and end the writing).
    func testATapOnTheFontRowStaysInTheSession() throws {
        try openText()
        app.openTextRow("style.font")
        let futura = app.buttons["style.font.Futura"]
        XCTAssertTrue(futura.waitForExistence(timeout: 5))
        let frame = futura.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: frame.maxX + 3, dy: frame.midY)).tap()
        sleep(1)
        XCTAssertTrue(app.buttons["text.row.back"].exists, "a tap between two chips ended the writing")
        origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        let selected = NSPredicate(format: "isSelected == true")
        expectation(for: selected, evaluatedWith: futura)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["text.row.back"].exists, "a tap on a chip ended the writing")
    }

    // MARK: Fast taps

    /// A double tap on Text: one block, one session, and the words land.
    func testDoubleTapOnTextOpensOneSession() {
        app.buttons["mode.text"].doubleTap()
        let field = any("canvas.textEditor")
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no writing session: \(canvasState())")
        field.typeText("one")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "one").count
                       + app.staticTexts.matching(NSPredicate(format: "label == 'one'")).count > 0, true)
        let texts = (canvasState()["elements"] as? [[String: Any]] ?? []).filter { $0["kind"] as? String == "text" }
        XCTAssertEqual(texts.count, 1, "\(texts)")
        XCTAssertEqual(texts.first?["text"] as? String, "one")
    }

    /// Text, then Sticker as fast as a finger goes: wherever the second tap
    /// lands, no empty block is left behind on the page.
    func testTextThenStickerLeavesNoEmptyBlock() {
        // Where Sticker sits now, as a screen point: the tool bar may be
        // gone by the time the second tap lands.
        let frame = app.buttons["mode.sticker"].frame
        let sticker = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        app.buttons["mode.text"].tap()
        sticker.tap()
        sleep(2)
        if app.buttons["sticker.tab.make"].exists {
            app.buttons["mode.sticker"].tap()
            XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
            sleep(1)
        }
        let state = canvasState()
        let writing = state["writing"] as? String ?? ""
        let texts = (state["elements"] as? [[String: Any]] ?? []).filter { $0["kind"] as? String == "text" }
        if writing.isEmpty {
            XCTAssertTrue(texts.isEmpty, "an empty block outlived its session: \(texts)")
        } else {
            XCTAssertEqual(texts.count, 1, "one session, one block: \(texts)")
        }
    }
}
