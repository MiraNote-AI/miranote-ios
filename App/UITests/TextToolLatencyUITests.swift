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
