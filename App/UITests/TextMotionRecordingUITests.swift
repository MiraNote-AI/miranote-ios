import XCTest

/// #162: scenes to film with `xcrun simctl io <device> recordVideo` -- the
/// Text open and an empty exit, frame by frame. Skipped unless the runner
/// gets REC_SCENE (set TEST_RUNNER_REC_SCENE on xcodebuild). Each tap
/// prints `REC-TAP <name> <epoch>` so the film can be cut at the tap.
final class TextMotionRecordingUITests: XCTestCase {
    private var app: XCUIApplication!
    private var scene: String { ProcessInfo.processInfo.environment["REC_SCENE"] ?? "" }

    override func setUpWithError() throws {
        try XCTSkipIf(scene.isEmpty, "film scenes run only with REC_SCENE")
        continueAfterFailure = false
    }

    private func mark(_ name: String) {
        print(String(format: "REC-TAP %@ %.3f", name, Date().timeIntervalSince1970))
    }

    private func launchCanvas() {
        app = XCUIApplication()
        let extra = ProcessInfo.processInfo.environment["REC_ARGS"] ?? ""
        app.launchArguments = ["-UITEST"] + extra.split(separator: " ").map(String.init)
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        sleep(2)
    }

    private func write(_ words: String) {
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "canvas.textEditor").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    private func probe() -> String {
        app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch.label
    }

    /// Three opens (REC_ROUNDS to change; the first after launch is the
    /// cold keyboard), each held 2 s, then Cancel.
    private func filmOpens(_ name: String) {
        let rounds = Int(ProcessInfo.processInfo.environment["REC_ROUNDS"] ?? "") ?? 3
        for round in 1...rounds {
            mark("\(name)-\(round)")
            app.buttons["mode.text"].tap()
            sleep(2)
            let state = probe()
            if let range = state.range(of: "\"textOpen\":\\{[^}]*\\}", options: .regularExpression) {
                print("REC-PROBE \(name)-\(round) \(state[range])")
            }
            app.buttons["text.cancel"].tap()
            sleep(2)
        }
    }

    func testFilm() throws {
        switch scene {
        case "open-empty":
            launchCanvas()
            filmOpens("open-empty")
        case "open-full":
            launchCanvas()
            write("first line of the day")
            write("second, a little longer than the first one")
            write("third")
            sleep(2)
            filmOpens("open-full")
        case "exit-empty":
            launchCanvas()
            for round in 1...3 {
                app.buttons["mode.text"].tap()
                sleep(2)
                mark("exit-empty-\(round)")
                // Bare page above the new block.
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 200, dy: 160)).tap()
                sleep(2)
            }
        default:
            XCTFail("unknown REC_SCENE \(scene)")
        }
    }
}
