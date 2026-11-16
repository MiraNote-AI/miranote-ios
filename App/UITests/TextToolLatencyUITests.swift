import XCTest

/// #162: a tap on Text brings the keyboard and the text tools up at once,
/// with no stall -- and the screen settles exactly where it did before the
/// fix. Times come from the -UITEST probe's `textOpen` entry (tap ->
/// keyboardDidShow, measured in the app, not by the test runner).
final class TextToolLatencyUITests: XCTestCase {
    private var app: XCUIApplication!

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

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func canvasState() -> [String: Any] {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let data = probe.label.data(using: .utf8) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// The probe's `textOpen` once `opens` has reached `count` (it refreshes
    /// every 0.25 s).
    private func textOpen(after count: Int) -> [String: Any] {
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

    /// Taps Text and waits for the software keyboard; skips the test when
    /// the simulator has a hardware keyboard (no keyboard ever rises).
    private func openText() throws {
        app.buttons["mode.text"].tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("hardware keyboard connected: no software keyboard to time")
        }
    }

    private func cancelText() {
        app.buttons["text.cancel"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    private func write(_ words: String) {
        app.buttons["mode.text"].tap()
        let field = any("canvas.textEditor")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

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
            cancelText()
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
            cancelText()
        }
    }

    /// No keyboard rise heard (as with some hardware keyboards): the tools
    /// still show, after the wait for one, and can be used.
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
        XCTAssertGreaterThanOrEqual(row["toolsVisibleMs"] as? Int ?? -1, 0, "tools never showed: \(row)")
        // And they work: a tap on a font sets it.
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
        XCTAssertTrue(app.buttons["keyboard.done"].waitForExistence(timeout: 5))
        app.buttons["keyboard.done"].tap()
        let down = NSPredicate(format: "exists == false")
        expectation(for: down, evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
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

    /// While the tools ride up the font row is a still copy: a tap on it,
    /// even between two chips, stays in the session and sets the font (it
    /// used to fall through to the page and end the writing).
    func testATapOnTheRisingFontRowStaysInTheSession() throws {
        app.terminate()
        app.launchArguments = ["-UITEST", "-HOLD_TOOLS_RIDING"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        try openText()
        let futura = app.buttons["style.font.Futura"]
        XCTAssertTrue(futura.waitForExistence(timeout: 5))
        let frame = futura.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: frame.maxX + 3, dy: frame.midY)).tap()
        sleep(1)
        XCTAssertTrue(app.buttons["text.cancel"].exists, "a tap between two chips ended the writing")
        origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        let selected = NSPredicate(format: "isSelected == true")
        expectation(for: selected, evaluatedWith: futura)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["text.cancel"].exists, "a tap on a chip ended the writing")
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
            app.buttons["nav.leading"].tap()
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

    // MARK: The keyboard's color

    /// How light the keyboard's key caps are once it has landed, 0-1: the
    /// dark keyboard's caps are gray (about 0.4), the light one's white.
    /// Sampled off the letter, a fifth in from the Q key's left edge.
    private func keyCapLuminance() -> Double {
        let key = app.keyboards.keys.matching(NSPredicate(format: "label ==[c] 'q'")).firstMatch
        guard key.waitForExistence(timeout: 5),
              let image = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
        let scale = Double(image.width) / Double(app.windows.firstMatch.frame.width)
        let column = Int((key.frame.minX + key.frame.width * 0.2) * scale)
        let row = Int((key.frame.minY + key.frame.height * 0.3) * scale)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -column, y: row - image.height + 1, width: image.width, height: image.height))
        return (0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2])) / 255
    }

    /// The keyboard rises dark: never light first and swapped on the way
    /// up (a swap mid-rise stalls or skips the rise -- up to 365 ms with no
    /// frame on the iPhone 17 sim). No reload once it has started to rise.
    func testKeyboardRisesDarkWithoutASwap() throws {
        for open in 1...3 {
            try openText()
            let row = textOpen(after: open)
            XCTAssertEqual(row["lateReloads"] as? Int, 0, "open \(open): swapped mid-rise: \(row)")
            sleep(1)
            let caps = keyCapLuminance()
            XCTAssertGreaterThan(caps, 0, "open \(open): no Q key")
            XCTAssertLessThan(caps, 0.6, "open \(open): the keyboard is light (caps \(caps))")
            cancelText()
        }
    }

    // MARK: Leaving with nothing written

    /// Text, nothing written, a tap on the bare page: the page holds still
    /// while the keyboard goes. (It used to shrink above the falling
    /// keyboard at once, then grow back down with it -- a jump.)
    func testEmptyExitKeepsThePageStill() throws {
        try openText()
        sleep(1)
        // Bare page above the new block.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 200, dy: 160)).tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        sleep(1)
        let state = canvasState()
        XCTAssertEqual(state["writing"] as? String ?? "", "", "the session ended")
        let shrink = (state["textOpen"] as? [String: Any])?["exitShrink"] as? Int
        XCTAssertNotNil(shrink, "\(state["textOpen"] ?? "-")")
        XCTAssertLessThanOrEqual(shrink ?? 999, 1, "the page shrank \(shrink ?? -1) pt as the keyboard left")
    }

    // MARK: The page under the rising tools

    /// On a full page the new block lands low and the page scrolls it
    /// clear of the tools: one scroll, not one per step of the tools'
    /// rise (three stacked scrolls read as a stutter).
    func testLowBlockScrollsClearOnce() throws {
        write("first line of the day")
        write("second, a little longer than the first one")
        write("third")
        try openText()
        sleep(1)
        let open = textOpen(after: 4)
        XCTAssertEqual(open["clearScrolls"] as? Int, 1, "\(open)")
    }

    // MARK: Settled layout

    /// Frames recorded on dev 8adad30, iPhone 17, iOS 26.5, before any
    /// change for #162: the fix must not move what the user sees.
    private static let settledEmptyPage: [String: CGRect] = [
        "canvas.textEditor": CGRect(x: 90.6, y: 237.0, width: 220.9, height: 22.5),
        "keyboard": CGRect(x: 0, y: 583, width: 402, height: 233),
        "keyboard.done": CGRect(x: 326, y: 59, width: 60, height: 44),
        "style.font.Josefin": CGRect(x: 88, y: 415.3, width: 65, height: 35),
        "style.mic": CGRect(x: 16, y: 499, width: 370, height: 36),
        "text.cancel": CGRect(x: 16, y: 59, width: 70, height: 44)
    ]
    private static let settledLowBlock: [String: CGRect] = [
        "canvas.textEditor": CGRect(x: 90.6, y: 136.0, width: 220.9, height: 22.5),
        "keyboard": CGRect(x: 0, y: 583, width: 402, height: 233),
        "keyboard.done": CGRect(x: 326, y: 59, width: 60, height: 44),
        "style.font.Josefin": CGRect(x: 88, y: 415.3, width: 65, height: 35),
        "style.mic": CGRect(x: 16, y: 499, width: 370, height: 36),
        "text.cancel": CGRect(x: 16, y: 59, width: 70, height: 44)
    ]

    private static let settledIDs = ["canvas.textEditor", "style.mic", "style.font.Josefin",
                                     "keyboard.done", "text.cancel"]

    private func settledFrames() throws -> [String: CGRect] {
        try openText()
        sleep(1)
        var frames: [String: CGRect] = [:]
        for id in Self.settledIDs {
            XCTAssertTrue(any(id).waitForExistence(timeout: 5), id)
            frames[id] = any(id).frame
        }
        frames["keyboard"] = app.keyboards.firstMatch.frame
        return frames
    }

    /// The block's settled top on a full page varies on dev itself: 136
    /// when the board scrolls it clear of the tools, 253.4 in about one run
    /// in ten where it is placed already clear. Both were recorded before
    /// the fix; any other top is a change.
    private static let lowBlockTops: [CGFloat] = [136.0, 253.4]

    private func assertFrames(_ frames: [String: CGRect], equal expected: [String: CGRect], _ name: String,
                              editorTops: [CGFloat]? = nil) {
        let printed = frames.sorted { $0.key < $1.key }
            .map { id, rect in
                "\"\(id)\": CGRect(x: \(rect.minX), y: \(rect.minY), width: \(rect.width), height: \(rect.height))"
            }
        print("settled-\(name): [\(printed.joined(separator: ", "))]")
        XCTAssertEqual(Set(frames.keys), Set(expected.keys), "\(name): recorded frames missing")
        for (id, frame) in frames {
            guard let want = expected[id] else { continue }
            XCTAssertEqual(frame.minX, want.minX, accuracy: 0.5, "\(name) \(id) x")
            if id == "canvas.textEditor", let editorTops {
                XCTAssertTrue(editorTops.contains { abs($0 - frame.minY) <= 0.5 }, "\(name) \(id) y \(frame.minY)")
            } else {
                XCTAssertEqual(frame.minY, want.minY, accuracy: 0.5, "\(name) \(id) y")
            }
            XCTAssertEqual(frame.width, want.width, accuracy: 0.5, "\(name) \(id) width")
            XCTAssertEqual(frame.height, want.height, accuracy: 0.5, "\(name) \(id) height")
        }
    }

    /// The settled screen after a Text tap, on an empty page and on a page
    /// whose new block lands low (the page scrolls it clear of the tools).
    func testTextOpenFinalLayoutUnchanged() throws {
        // The recorded frames are iPhone 17's (402 pt wide).
        guard abs(app.windows.firstMatch.frame.width - 402) < 0.5 else {
            throw XCTSkip("settled frames are recorded on iPhone 17 only")
        }
        assertFrames(try settledFrames(), equal: Self.settledEmptyPage, "empty page")
        cancelText()
        write("first line of the day")
        write("second, a little longer than the first one")
        write("third")
        assertFrames(try settledFrames(), equal: Self.settledLowBlock, "low block",
                     editorTops: Self.lowBlockTops)
    }
}
