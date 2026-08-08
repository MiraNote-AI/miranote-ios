import XCTest

/// Demo-video shot driver (miranote-demo pipeline). NOT a test: it runs
/// the whole shotlist in ONE app session against LIVE backends while
/// scripts/record.py records each shot as its own video.
///
/// Per-shot handshake over /tmp (simulator processes share the host FS):
///   1. test finishes any `pre_wait` (the off-camera AI wait), then
///      writes  /tmp/demo_ready_<shot>
///   2. record.py arms simctl recordVideo, then writes /tmp/demo_go_<shot>
///   3. test runs the shot's actions, emits DEMOEVT out
///   4. record.py stops the recorder on the out event
///
/// Timestamps are used for nothing but logging -- simctl recordVideo is
/// VFR and its clock cannot be trusted (learned the hard way).
final class DemoRecorderUITests: XCTestCase {
    func testRunDemoSegment() throws {
        guard let b64 = ProcessInfo.processInfo.environment["DEMO_SEGMENT_B64"],
              let data = Data(base64Encoded: b64),
              let segment = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let shots = segment["shots"] as? [[String: Any]] else {
            throw XCTSkip("no DEMO_SEGMENT_B64 -- demo recorder is driven by scripts/record.py")
        }
        continueAfterFailure = false

        let app = XCUIApplication()
        // Live services on purpose (every AI answer is real); the flag only
        // unlocks the staged-photo Samples chip (see meta.honesty).
        app.launchArguments = ["-DEMO-SAMPLES"]
        app.launch()
        emit(["event": "app_ready", "t": now()])

        for shot in shots {
            let id = shot["id"] as? String ?? "?"
            // pre_actions run OFF CAMERA (before the recorder handshake):
            // used to rebuild prerequisite state on surgical re-records.
            for action in shot["pre_actions"] as? [[String: Any]] ?? [] {
                run(action, in: app, shot: id)
            }
            if let preWait = shot["pre_wait"] as? [String: Any] {
                emit(["event": "pre_wait_start", "shot": id, "t": now()])
                waitFor(preWait, in: app, shot: id)
                emit(["event": "pre_wait_done", "shot": id, "t": now()])
            }
            // handshake: tell the director this shot is staged, then hold
            // for the recorder before touching anything.
            let ready = URL(fileURLWithPath: "/tmp/demo_ready_\(id)")
            let go = "/tmp/demo_go_\(id)"
            try? Data().write(to: ready)
            let armDeadline = Date().addingTimeInterval(30)
            while !FileManager.default.fileExists(atPath: go) {
                if Date() > armDeadline { XCTFail("director never armed \(id)"); return }
                Thread.sleep(forTimeInterval: 0.1)
            }
            emit(["event": "in", "shot": id, "t": now()])
            let hold = shot["hold_s"] as? Double ?? 0
            let start = Date()
            for action in shot["actions"] as? [[String: Any]] ?? [] {
                run(action, in: app, shot: id)
            }
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < hold {
                Thread.sleep(forTimeInterval: hold - elapsed)
            }
            emit(["event": "out", "shot": id, "t": now()])
        }
    }

    private func run(_ action: [String: Any], in app: XCUIApplication, shot: String) {
        let type = action["type"] as? String ?? ""
        switch type {
        case "settle":
            Thread.sleep(forTimeInterval: Double(action["ms"] as? Int ?? 500) / 1000)
        case "tap_id":
            tap(element(app, id: action["id"] as? String ?? ""), label: type)
        case "tap_text":
            let text = action["text"] as? String ?? ""
            let button = app.buttons[text].firstMatch
            tap(button.waitForExistence(timeout: 10) ? button : app.staticTexts[text].firstMatch, label: type)
        case "type_field":
            let field = element(app, id: action["id"] as? String ?? "")
            XCTAssertTrue(field.waitForExistence(timeout: 15), "field missing: \(action)")
            field.tap()
            field.typeText(action["text"] as? String ?? "")
        case "tap_first_match":
            if let prefix = action["prefix_id"] as? String {
                let match = app.descendants(matching: .any).matching(
                    NSPredicate(format: "identifier BEGINSWITH %@", prefix)
                ).firstMatch
                tap(match, label: type)
            }
        case "wait_id", "wait_text", "wait_text_static":
            waitFor(action, in: app, shot: shot)
        default:
            XCTFail("unknown action type: \(type)")
        }
    }

    /// Shared by on-camera wait actions and off-camera pre_waits: land the
    /// element or die fast on a Mira failure card.
    private func waitFor(_ spec: [String: Any], in app: XCUIApplication, shot: String) {
        let target: XCUIElement
        if let id = spec["id"] as? String {
            target = element(app, id: id)
        } else if spec["type"] as? String == "wait_text_static" {
            target = app.staticTexts[spec["text"] as? String ?? ""].firstMatch
        } else {
            target = app.buttons[spec["text"] as? String ?? ""].firstMatch
        }
        let timeout = Double(spec["timeout_s"] as? Int ?? 120)
        let failure = app.descendants(matching: .any)["mira.failure"].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if target.exists { return }
            if failure.exists {
                XCTFail("mira turn failed while waiting in \(shot): \(spec)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("wait timed out in \(shot): \(spec)")
    }

    private func element(_ app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func tap(_ element: XCUIElement, label: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "element missing for \(label)")
        element.tap()
    }

    private func now() -> Double { Date().timeIntervalSince1970 }

    private func emit(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        print("DEMOEVT \(json)")
    }
}
