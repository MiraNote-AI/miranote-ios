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
        case "open-font":
            // A block set in a later face, so the font row opens scrolled.
            launchCanvas()
            app.buttons["mode.text"].tap()
            let field = app.descendants(matching: .any).matching(identifier: "canvas.textEditor").firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            app.buttons["style.font.Didot"].tap()
            field.typeText("set in didot")
            app.buttons["keyboard.done"].tap()
            let block = app.staticTexts["set in didot"]
            XCTAssertTrue(block.waitForExistence(timeout: 5))
            sleep(2)
            let rounds = Int(ProcessInfo.processInfo.environment["REC_ROUNDS"] ?? "") ?? 3
            for round in 1...rounds {
                mark("open-font-\(round)")
                // Done leaves the block selected: one tap writes again.
                block.tap()
                sleep(2)
                let state = probe()
                if let range = state.range(of: "\"textOpen\":\\{[^}]*\\}", options: .regularExpression) {
                    print("REC-PROBE open-font-\(round) \(state[range])")
                }
                app.buttons["keyboard.done"].tap()
                sleep(2)
            }
        case "done-scroll":
            // Words, Done, then the page dragged up and back at once.
            launchCanvas()
            let rounds = Int(ProcessInfo.processInfo.environment["REC_ROUNDS"] ?? "") ?? 3
            for round in 1...rounds {
                app.buttons["mode.text"].tap()
                let field = app.descendants(matching: .any).matching(identifier: "canvas.textEditor").firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                field.typeText("line \(round)")
                mark("done-scroll-\(round)")
                app.buttons["keyboard.done"].tap()
                // Slowly, on the page's bare right edge, through the
                // keyboard's fall and the page settling after it.
                let page = app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.45))
                page.press(forDuration: 0.02, thenDragTo: page.withOffset(CGVector(dx: 0, dy: -300)),
                           withVelocity: 300, thenHoldForDuration: 0.1)
                usleep(300_000)
                page.press(forDuration: 0.02, thenDragTo: page.withOffset(CGVector(dx: 0, dy: 300)),
                           withVelocity: 300, thenHoldForDuration: 0.1)
                sleep(2)
            }
        case "done-back":
            // A block low on a full page scrolls it up; Done takes it back.
            launchCanvas()
            app.buttons["mode.image"].tap()
            app.buttons["image.library.open"].tap()
            let first = app.descendants(matching: .any).matching(identifier: "image.library.photo.0").firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            for index in 0..<3 {
                app.descendants(matching: .any).matching(identifier: "image.library.photo.\(index)").firstMatch.tap()
            }
            app.buttons["image.composer.add"].tap()
            app.buttons["nav.trailing"].tap()
            XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
            app.buttons["mode.text"].tap()
            let field = app.descendants(matching: .any).matching(identifier: "canvas.textEditor").firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText("lunch by the river")
            sleep(2)
            mark("done-back-new")
            app.buttons["keyboard.done"].tap()
            sleep(2)
            let block = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'lunch by the river'")).firstMatch
            let rounds = Int(ProcessInfo.processInfo.environment["REC_ROUNDS"] ?? "") ?? 3
            for round in 1...rounds {
                block.tap()
                if !field.waitForExistence(timeout: 2) { block.tap() }
                sleep(2)
                mark("done-back-\(round)")
                app.buttons["keyboard.done"].tap()
                sleep(2)
            }
        case "mira-open":
            // The Mira chat field's keyboard, to compare with Text's.
            launchCanvas()
            let rounds = Int(ProcessInfo.processInfo.environment["REC_ROUNDS"] ?? "") ?? 3
            for round in 1...rounds {
                mark("mira-open-\(round)")
                app.buttons["mira.composer"].tap()
                sleep(2)
                let state = probe()
                if let range = state.range(of: "\"textOpen\":\\{[^}]*\\}", options: .regularExpression) {
                    print("REC-PROBE mira-open-\(round) \(state[range])")
                }
                app.buttons["nav.trailing"].firstMatch.tap()
                sleep(2)
            }
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
