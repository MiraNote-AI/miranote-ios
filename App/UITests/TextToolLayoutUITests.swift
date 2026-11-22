import XCTest

/// #162: what the screen shows through a Text open -- the keyboard's
/// color, the page as the tools rise and on an empty exit, and the settled
/// frames (re-recorded for #205's clear page).
final class TextToolLayoutUITests: TextToolUITestCase {
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
    /// frame on the iPhone 17 sim). The field asks for it dark as it starts.
    func testKeyboardRisesDarkWithoutASwap() throws {
        for open in 1...3 {
            try openText()
            let row = textOpen(after: open)
            XCTAssertEqual(row["lightRises"] as? Int, 0, "open \(open): rose light: \(row)")
            sleep(1)
            let caps = keyCapLuminance()
            XCTAssertGreaterThan(caps, 0, "open \(open): no Q key")
            XCTAssertLessThan(caps, 0.6, "open \(open): the keyboard is light (caps \(caps))")
            leaveText()
        }
    }

    /// And stays dark as words are typed on it: real key taps, not
    /// typeText (the first keystrokes used to turn it light).
    func testKeyboardStaysDarkWhileTyping() throws {
        try openText()
        _ = textOpen(after: 1)
        for letter in ["l", "u", "n", "c", "h"] {
            app.keyboards.keys.matching(NSPredicate(format: "label ==[c] %@", letter)).firstMatch.tap()
        }
        sleep(1)
        let caps = keyCapLuminance()
        XCTAssertGreaterThan(caps, 0, "no Q key")
        XCTAssertLessThan(caps, 0.6, "the keyboard turned light while typing (caps \(caps))")
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

    /// Frames recorded for #205 PR 2 (text on a clear page), iPhone 17 Pro
    /// sim, iOS 26.3: the layout changed on purpose -- Back joins the tool
    /// bar, the chat box with its mic replaces the dictation strip, and the
    /// header keeps Home / Save (greyed). #162's fix must not move these.
    /// PR 4: the slot shows one row, so the text row's Aa key stands in for
    /// the font row's Josefin chip; nothing else moved.
    private static let settledEmptyPage: [String: CGRect] = [
        "canvas.textEditor": CGRect(x: 90.6, y: 237.0, width: 220.9, height: 22.5),
        "keyboard": CGRect(x: 0, y: 583, width: 402, height: 233),
        "keyboard.done": CGRect(x: 12, y: 433, width: 44, height: 44),
        "nav.leading": CGRect(x: 16, y: 59, width: 70, height: 44),
        "style.font": CGRect(x: 60.3, y: 433, width: 44, height: 44),
        "style.mic": CGRect(x: 332, y: 486, width: 44, height: 44)
    ]
    private static let settledLowBlock: [String: CGRect] = [
        "canvas.textEditor": CGRect(x: 90.6, y: 136.0, width: 220.9, height: 22.5),
        "keyboard": CGRect(x: 0, y: 583, width: 402, height: 233),
        "keyboard.done": CGRect(x: 12, y: 433, width: 44, height: 44),
        "nav.leading": CGRect(x: 16, y: 59, width: 70, height: 44),
        "style.font": CGRect(x: 60.3, y: 433, width: 44, height: 44),
        "style.mic": CGRect(x: 332, y: 486, width: 44, height: 44)
    ]

    private static let settledIDs = ["canvas.textEditor", "style.mic", "style.font",
                                     "keyboard.done", "nav.leading"]

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
    /// in ten where it is placed already clear (still clear of #205's taller
    /// tools). Any other top is a change.
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
        leaveText()
        write("first line of the day")
        write("second, a little longer than the first one")
        write("third")
        assertFrames(try settledFrames(), equal: Self.settledLowBlock, "low block",
                     editorTops: Self.lowBlockTops)
    }
}
