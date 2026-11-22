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
    /// cold keyboard), each held 2 s, then Back.
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
            app.buttons["keyboard.done"].tap()
            sleep(2)
        }
    }

    func testFilm() throws {
        switch scene {
        case "open-empty": filmOpenEmpty()
        case "open-full": filmOpenFull()
        case "open-font": filmOpenFont()
        case "done-scroll": filmDoneScroll()
        case "done-back": filmDoneBack()
        case "mira-open": filmMiraOpen()
        case "exit-empty": filmExitEmpty()
        case "color-sheet": filmColorSheet()
        default: XCTFail("unknown REC_SCENE \(scene)")
        }
    }

    private func filmOpenEmpty() {
        launchCanvas()
        filmOpens("open-empty")
    }

    private func filmOpenFull() {
        launchCanvas()
        write("first line of the day")
        write("second, a little longer than the first one")
        write("third")
        sleep(2)
        filmOpens("open-full")
    }

    /// A block set in a later face (the font row used to open on it).
    private func filmOpenFont() {
        launchCanvas()
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "canvas.textEditor").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.openTextRow("style.font")
        app.buttons["style.font.Didot"].tap()
        field.typeText("set in didot")
        app.backToTextRow()
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
    }

    /// Words, Done, then the page dragged up and back at once.
    private func filmDoneScroll() {
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
    }

    /// A block low on a full page scrolls it up; Done takes it back.
    private func filmDoneBack() {
        launchCanvas()
        app.buttons["mode.image"].tap()
        app.buttons["image.library.open"].tap()
        let first = app.descendants(matching: .any).matching(identifier: "image.library.photo.0").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        for index in 0..<3 {
            app.descendants(matching: .any).matching(identifier: "image.library.photo.\(index)").firstMatch.tap()
        }
        app.buttons["image.composer.add"].tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "Add closes the Image tool")
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
    }

    /// The Mira chat field's keyboard, to compare with Text's.
    private func filmMiraOpen() {
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
    }

    /// The keyboard comes back after the custom color sheet with the color
    /// row (a snap row) open in the slot: the row must ride it with the
    /// chat box. A dark custom color fills the centered dot to film.
    private func filmColorSheet() {
        launchCanvas()
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "canvas.textEditor").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("ink")
        app.openTextRow("style.colors")
        let rounds = Int(ProcessInfo.processInfo.environment["REC_ROUNDS"] ?? "") ?? 3
        for round in 1...rounds {
            app.buttons["style.color.custom"].tap()
            let hex = app.textFields["colorSheet.hex"]
            XCTAssertTrue(hex.waitForExistence(timeout: 5))
            hex.tap()
            let current = (hex.value as? String) ?? ""
            hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 1))
            hex.typeText("11223\(round)\n")
            sleep(1)
            mark("color-sheet-\(round)")
            app.buttons["colorSheet.apply"].tap()
            sleep(2)
        }
    }

    private func filmExitEmpty() {
        launchCanvas()
        for round in 1...3 {
            app.buttons["mode.text"].tap()
            sleep(2)
            mark("exit-empty-\(round)")
            // Bare page above the new block.
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 200, dy: 160)).tap()
            sleep(2)
        }
    }
}
