import XCTest

/// A seeded monkey: random taps, long-presses, drags, tool switches, Done
/// and Cancel, strip holds, Home and background/foreground -- with the
/// slow-service hooks on -- checking the app's invariants after every
/// event through its -UITEST state probe ("debug.state"):
/// - no microphone on unless a strip, the recorder or the chat shows it
///   listening (or coming up);
/// - Done never leaves the block it ended overlapping something it did not
///   overlap when the writing began;
/// - no element off the page sideways or above its top;
/// - no crash.
/// On failure: the seed and the last 30 events.
///
/// Skipped unless MONKEY=1 reaches the test runner (xcodebuild passes
/// TEST_RUNNER_MONKEY=1 on as MONKEY=1). MONKEY_SEED and MONKEY_EVENTS
/// (default 300, keep batches at 1000 or fewer) pick the run.
final class MonkeyUITests: XCTestCase {
    private var app: XCUIApplication!
    private var rng = MonkeyRandom(seed: 0)
    private var events: [String] = []
    private var seed: UInt64 = 0
    /// Overlapping pairs when the current writing session began.
    private var overlapsAtSessionStart: Set<String>?
    private var writingBlock = ""
    /// What the run saw (a monkey that never reads the probe checks nothing).
    private var seen: [String: Int] = [:]
    private var atHome = false

    func testMonkey() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["MONKEY"] == "1" else { throw XCTSkip("Set TEST_RUNNER_MONKEY=1 to run the monkey.") }
        seed = env["MONKEY_SEED"].flatMap(UInt64.init) ?? UInt64(Date().timeIntervalSince1970)
        let count = env["MONKEY_EVENTS"].flatMap(Int.init) ?? 300
        rng = MonkeyRandom(seed: seed)
        continueAfterFailure = false

        app = XCUIApplication()
        // One slow service per run, so results land after the next events.
        let hooks: [[String]] = [
            ["-TRANSCRIBE_DELAY", "1500"], ["-MIC_START_DELAY", "700"], ["-AI_EDIT_DELAY", "2500"],
            ["-CHAT_DELAY", "2500"], ["-IMPORT_DELAY", "2000"], ["-TRANSCRIBE_FIRST_DELAY", "4000"]
        ]
        let hook = hooks[rng.int(0...hooks.count - 1)]
        app.launchArguments = ["-UITEST"] + hook
        app.launch()
        record("launch \(hook.joined(separator: " ")) seed \(seed)")
        enterEditor()

        for index in 0..<count {
            step()
            check()
            if index % 50 == 49 { print("[monkey] seed \(seed): \(index + 1) of \(count) events") }
        }
        let tally = seen.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        print("[monkey] seed \(seed): \(count) events, invariants held; seen: \(tally)")
        XCTAssertGreaterThan(seen["probe read"] ?? 0, count / 2, "the probe was hardly read: the run checked little")
    }

    // MARK: Events

    private func step() {
        if app.state != .runningForeground {
            app.activate()
            record("reactivate")
        }
        // Home stays in the tree under the editor's cover: only a hittable
        // Start means Home is showing.
        atHome = app.buttons["Start a memory"].isHittable
        if atHome, rng.chance(0.8) {
            enterEditor()
            return
        }
        switch rng.pick([(0, 30), (1, 6), (2, 8), (3, 10), (4, 12), (5, 8), (6, 6), (7, 4), (8, 3), (9, 5)]) {
        case 0: tapRandom()
        case 1: longPressRandom()
        case 2: dragRandom()
        case 3: tapNamed(["mode.text", "mode.voice", "mode.image", "mode.sticker", "mode.background"])
        case 4: tapNamed(["keyboard.done", "text.cancel", "editor.undo", "image.add", "photo.done"])
        case 5: typeWords()
        case 6: holdStrip()
        case 7: tapNamed(["recorder.record", "recorder.stop", "recorder.keep", "recorder.discard", "mira.keep"])
        case 8: backgroundAndReturn()
        default:
            let seconds = Double(rng.int(3...20)) / 10
            Thread.sleep(forTimeInterval: seconds)
            record("wait \(seconds) s")
        }
    }

    private func enterEditor() {
        let start = app.buttons["Start a memory"]
        guard start.waitForExistence(timeout: 5), start.isHittable else { return }
        start.tap()
        record("Start a memory")
    }

    /// Elements a finger can reach, by identifier or label: never one that
    /// opens system UI (picker, camera, share, Settings) the monkey cannot
    /// leave.
    private func targets() -> [(name: String, frame: CGRect)] {
        guard let root = try? app.snapshot() else { return [] }
        let screen = app.frame
        let denied = ["image.library.system", "image.library.more", "export.share", "export.print", "chat.hint",
                      "Settings", "Camera", "Share", "Print", "Choose Photos", "debug.state"]
        var found: [(String, CGRect)] = []
        func walk(_ node: XCUIElementSnapshot) {
            let name = node.identifier.isEmpty ? node.label : node.identifier
            let kinds: [XCUIElement.ElementType] = [.button, .staticText, .image, .textView, .textField, .cell]
            if kinds.contains(node.elementType), node.isEnabled, node.frame.width >= 8, node.frame.height >= 8,
               screen.contains(CGPoint(x: node.frame.midX, y: node.frame.midY)),
               !denied.contains(where: { name.contains($0) }),
               atHome || !(name == "Start a memory" || name.hasPrefix("collection.")) {
                found.append((name, node.frame))
            }
            node.children.forEach(walk)
        }
        walk(root)
        return found
    }

    private func point(_ frame: CGRect) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
    }

    private func randomPointOnScreen() -> XCUICoordinate {
        let frame = app.frame
        let x = Double(rng.int(10...Int(frame.width) - 10)), y = Double(rng.int(80...Int(frame.height) - 60))
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    private func tapRandom() {
        let all = targets()
        guard !all.isEmpty else {
            randomPointOnScreen().tap()
            record("tap somewhere")
            return
        }
        let target = all[rng.int(0...all.count - 1)]
        point(target.frame).tap()
        record("tap \(target.name)")
    }

    private func longPressRandom() {
        let all = targets()
        guard !all.isEmpty else { return }
        let target = all[rng.int(0...all.count - 1)]
        point(target.frame).press(forDuration: 0.9)
        record("long-press \(target.name)")
    }

    private func dragRandom() {
        let all = targets().filter { $0.name.hasPrefix("element.") || $0.frame.width > 60 }
        guard !all.isEmpty else { return }
        let target = all[rng.int(0...all.count - 1)]
        point(target.frame).press(forDuration: 0.15, thenDragTo: randomPointOnScreen())
        record("drag \(target.name)")
    }

    private func tapNamed(_ names: [String]) {
        let name = names[rng.int(0...names.count - 1)]
        let button = app.buttons[name]
        guard button.exists, button.isHittable else { return }
        button.tap()
        record("tap \(name)")
    }

    private func typeWords() {
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        guard field.exists else { return }
        let words = ["lunch", "by the river", "with Sam and Jo", "golden light", "a long walk home"]
        let text = words[rng.int(0...words.count - 1)] + " "
        field.typeText(text)
        record("type \"\(text)\"")
    }

    private func holdStrip() {
        let strips = ["style.mic", "mira.dictation", "chat.voice.hold"]
        let name = strips[rng.int(0...strips.count - 1)]
        let strip = app.buttons[name].exists ? app.buttons[name] : app.descendants(matching: .any)[name]
        guard strip.exists, strip.isHittable else { return }
        let seconds = Double(rng.int(1...25)) / 10
        strip.press(forDuration: seconds)
        record("hold \(name) \(seconds) s")
    }

    private func backgroundAndReturn() {
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: Double(rng.int(2...15)) / 10)
        app.activate()
        record("Home, then back")
    }

    private func record(_ event: String) {
        events.append(event)
        if events.count > 30 { events.removeFirst() }
        print("[monkey-event] \(event)")
    }

    // MARK: Invariants

    private func check() {
        guard app.state == .runningForeground || app.wait(for: .runningForeground, timeout: 3) else {
            fail("the app is not running (crashed?)", state: "")
            return
        }
        let probes = app.descendants(matching: .any).matching(identifier: "debug.state").allElementsBoundByIndex
        let states = probes.compactMap { probe -> [String: Any]? in
            guard let data = probe.label.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        guard !states.isEmpty else { return }
        seen["probe read", default: 0] += 1
        for state in states {
            seen["scene " + (state["scene"] as? String ?? "?"), default: 0] += 1
            if (state["micLive"] as? Int ?? 0) > 0 { seen["mic live", default: 0] += 1 }
            if !(state["writing"] as? String ?? "").isEmpty { seen["writing", default: 0] += 1 }
            if state["writingDown"] as? Bool == true { seen["words on their way", default: 0] += 1 }
            if !(state["photoEditing"] as? String ?? "").isEmpty { seen["photo editor", default: 0] += 1 }
        }
        let raw = probes.map(\.label).joined(separator: " | ")
        checkMicrophones(states, raw: raw)
        guard let canvas = states.first(where: { $0["scene"] as? String == "canvas" }) else {
            overlapsAtSessionStart = nil
            return
        }
        checkElements(canvas, raw: raw)
    }

    /// A live mic with nothing showing it: look again a second later (the
    /// probe refreshes four times a second) before failing.
    private func checkMicrophones(_ states: [[String: Any]], raw: String) {
        func unshown(_ states: [[String: Any]]) -> Bool {
            let live = states.compactMap { $0["micLive"] as? Int }.max() ?? 0
            let showing = states.contains { state in
                (state["listening"] as? [String: Bool])?.values.contains(true) ?? false
            }
            return live > 0 && !showing
        }
        guard unshown(states) else { return }
        Thread.sleep(forTimeInterval: 1.2)
        let again = app.descendants(matching: .any).matching(identifier: "debug.state").allElementsBoundByIndex
            .compactMap { probe -> [String: Any]? in
                probe.label.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            }
        if unshown(again) { fail("a microphone is on with nothing showing it listening", state: raw) }
    }

    private func checkElements(_ canvas: [String: Any], raw: String) {
        let width = canvas["pageWidth"] as? Double ?? 390
        let elements = canvas["elements"] as? [[String: Any]] ?? []
        for element in elements {
            let x = element["x"] as? Double ?? 0, y = element["y"] as? Double ?? 0
            if x < 0 || x > width || y < 0 {
                fail("an element is off the page at (\(x), \(y))", state: raw)
            }
        }
        let writing = canvas["writing"] as? String ?? ""
        let pairs = Self.overlaps(elements)
        if !writing.isEmpty {
            if overlapsAtSessionStart == nil || writing != writingBlock {
                overlapsAtSessionStart = pairs
                writingBlock = writing
            }
        } else if let before = overlapsAtSessionStart, events.last?.contains("keyboard.done") == true {
            let new = pairs.subtracting(before).filter { $0.contains(writingBlock) }
            if !new.isEmpty { fail("Done left the block it ended overlapping another element", state: raw) }
            overlapsAtSessionStart = nil
        } else {
            overlapsAtSessionStart = nil
        }
    }

    private static func overlaps(_ elements: [[String: Any]]) -> Set<String> {
        func frame(_ element: [String: Any]) -> CGRect {
            let w = element["w"] as? Double ?? 0, h = element["h"] as? Double ?? 0
            return CGRect(x: (element["x"] as? Double ?? 0) - w / 2, y: (element["y"] as? Double ?? 0) - h / 2,
                          width: w, height: h)
        }
        var pairs: Set<String> = []
        for (index, lhs) in elements.enumerated() {
            for rhs in elements[(index + 1)...] {
                let shared = frame(lhs).intersection(frame(rhs))
                guard !shared.isNull, shared.width > 1, shared.height > 1 else { continue }
                let ids = [lhs["id"] as? String ?? "", rhs["id"] as? String ?? ""].sorted()
                pairs.insert(ids.joined(separator: "+"))
            }
        }
        return pairs
    }

    private func fail(_ message: String, state: String) {
        let trail = events.enumerated().map { "  \($0.offset): \($0.element)" }.joined(separator: "\n")
        XCTFail("monkey seed \(seed): \(message)\nlast events:\n\(trail)\nprobe: \(state)")
    }
}

/// SplitMix64, as the Kit's sequence harness: the same seed, the same run.
struct MonkeyRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }

    mutating func chance(_ probability: Double) -> Bool { Double.random(in: 0..<1, using: &self) < probability }

    mutating func pick(_ weighted: [(Int, Int)]) -> Int {
        var roll = int(0...weighted.reduce(0) { $0 + $1.1 } - 1)
        for (value, weight) in weighted {
            if roll < weight { return value }
            roll -= weight
        }
        return weighted[0].0
    }
}
