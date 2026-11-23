import XCTest

/// What a Save does to the star jar (#206): an edited page's star shows
/// its new face at once, a never-saved draft's first Save flies in, and
/// the fold keeps #212's rules (#234): a tap or the app leaving lands the
/// star at once, and under Reduce Motion it fades in.
final class StarJarSaveUITests: XCTestCase {
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

    private func openJar() {
        let entry = app.buttons["home.starJar"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()
        XCTAssertTrue(app.staticTexts["Star jar"].waitForExistence(timeout: 5))
    }

    /// The element's average color, 0-255 per channel.
    private func averageColor(of element: XCUIElement) -> [Double] {
        guard let image = element.screenshot().image.cgImage else { return [0, 0, 0] }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [0, 0, 0] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var sums = [0.0, 0.0, 0.0]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<3 { sums[channel] += Double(pixels[index + channel]) }
        }
        return sums.map { $0 / Double(width * height) }
    }

    private func difference(_ lhs: [Double], _ rhs: [Double]) -> Double {
        zip(lhs, rhs).map { abs($0 - $1) }.reduce(0, +)
    }

    /// A seeded page's star is baked when the jar first shows it. Held
    /// open, painted lilac and saved, it is a new star back in that same
    /// jar -- not only in a jar opened afresh.
    func testAPageEditedFromTheJarShowsItsNewStarThere() {
        openJar()
        let star = app.buttons["jar.star.Slow morning, good coffee"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        sleep(3)
        let before = averageColor(of: star)

        star.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["reading.edit"].waitForExistence(timeout: 5))
        app.buttons["reading.edit"].tap()
        XCTAssertTrue(app.buttons["mode.background"].waitForExistence(timeout: 5))
        app.openBackgroundRow("color")
        let lilac = app.buttons["background.color.#E6D9F0"]
        XCTAssertTrue(lilac.waitForExistence(timeout: 5))
        lilac.tap()
        app.closeBackground()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["reading.back"].waitForExistence(timeout: 5))
        app.buttons["reading.back"].tap()
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        sleep(2)
        let back = averageColor(of: star)

        app.buttons["Home"].tap()
        openJar()
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        sleep(3)
        let afresh = averageColor(of: star)
        XCTAssertGreaterThan(difference(before, afresh), 15, "lilac paper makes a new star: \(before) -> \(afresh)")
        XCTAssertLessThan(difference(back, afresh), 3, "the jar it was edited from shows it too: \(back) vs \(afresh)")
    }

    /// #205 R5A: Save is greyed while Background is open, so a painting
    /// cannot be saved half way from the header. Closed mid-painting, the
    /// page saves as it shows: one star, and the painting that comes after
    /// the Save never reaches the saved page.
    func testClosingBackgroundMidPaintingThenSaveFilesThePageAsShown() {
        app.terminate()
        app.launchArguments = ["-UITEST", "-GENERATE_DELAY", "4000"]
        app.launch()
        let jar = app.buttons["home.starJar"]
        XCTAssertTrue(jar.waitForExistence(timeout: 8))
        XCTAssertEqual(jar.value as? String, "0")
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Lake day")
        app.buttons["keyboard.done"].tap()

        app.openBackground()
        let words = app.textFields["background.apply.input"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap()
        words.typeText("a soft sunset glow")
        app.buttons["background.apply"].tap()
        XCTAssertTrue(app.staticTexts["background.status"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Save waits for the tool to close")
        app.buttons["background.back"].tap()
        XCTAssertTrue(app.buttons["mode.background"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Save"].tap()

        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: jar)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 6), .completed, "the star lands once")
        // Past the painting's own time.
        sleep(5)
        XCTAssertEqual(jar.value as? String, "1", "and only once")
        openJar()
        let star = app.buttons["jar.star.Lake day"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        star.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["reading.edit"].waitForExistence(timeout: 5))
        app.buttons["reading.edit"].tap()
        XCTAssertTrue(app.buttons["mode.background"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.backdrop, "", "the late painting never reached the saved page: \(app.canvasProbe.label)")
    }

    /// A Mira chat draft has never been saved: its first Save makes it a
    /// star, which flies into the jar circle like a new page's.
    func testAChatDraftsFirstSaveFliesIntoTheJar() {
        let jar = app.buttons["home.starJar"]
        XCTAssertTrue(jar.waitForExistence(timeout: 8))
        XCTAssertEqual(jar.value as? String, "0")
        app.askFromHome("draft me a noodle page")
        let card = app.buttons["chat.draft.open"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.staticTexts["Drafted by Mira"].waitForExistence(timeout: 5))

        app.buttons["Save"].tap()
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: jar)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 6), .completed, "the star lands once")
        sleep(2)
        XCTAssertEqual(jar.value as? String, "1", "and only once")
    }

    // MARK: The fold's rules

    /// Home's flow as its debug probe reports it.
    private var homeState: [String: Any] {
        let probes = app.descendants(matching: .any).matching(identifier: "debug.state").allElementsBoundByIndex
        for probe in probes {
            guard let data = probe.label.data(using: .utf8),
                  let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  state["scene"] as? String == "home" else { continue }
            return state
        }
        return [:]
    }

    private func relaunch(_ arguments: [String]) {
        app.terminate()
        app.launchArguments = ["-UITEST"] + arguments
        app.launch()
    }

    /// A new page of words, saved from the editor.
    private func saveNewPage() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("A happy picnic")
        app.buttons["keyboard.done"].tap()
        app.buttons["Save"].tap()
    }

    private func waitUntil(_ timeout: TimeInterval, _ message: @autoclosure () -> String,
                           _ condition: @escaping () -> Bool) {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [met], timeout: timeout), .completed, message())
    }

    /// The fold is playing: its star is on its way, not in the jar yet.
    private func waitForTheFold(_ jar: XCUIElement) {
        waitUntil(8, "the fold plays: \(homeState)") { self.homeState["starArriving"] as? Bool == true }
        sleep(2)
        XCTAssertEqual(jar.value as? String, "0", "2 s into an 18 s fold, the star is not in yet")
    }

    /// The star is in the jar, once, and nothing is on its way.
    private func assertLandedOnce(_ jar: XCUIElement, within timeout: TimeInterval, _ message: String) {
        waitUntil(timeout, "\(message): \(homeState)") {
            jar.value as? String == "1" && self.homeState["starArriving"] as? Bool == false
        }
        sleep(3)
        XCTAssertEqual(jar.value as? String, "1", "\(message), once")
    }

    /// #212's rule, kept by design X: a tap on Home during the fold lands
    /// the star at once. `-STAR_SLOW 10` makes the fold 18 s long, so the
    /// tap is surely mid-fold and "at once" is well before its end.
    func testATapDuringTheFoldLandsTheStarAtOnce() {
        relaunch(["-STAR_SLOW", "10"])
        let jar = app.buttons["home.starJar"]
        XCTAssertTrue(jar.waitForExistence(timeout: 8))
        saveNewPage()
        waitForTheFold(jar)
        // The headline, which no button takes.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).tap()
        assertLandedOnce(jar, within: 4, "a tap lands it at once")
    }

    /// #212's rule, kept by design X: the app leaving during the fold
    /// lands the star; back on Home it is in, and no fold plays again.
    func testLeavingTheAppDuringTheFoldLandsTheStar() {
        relaunch(["-STAR_SLOW", "10"])
        let jar = app.buttons["home.starJar"]
        XCTAssertTrue(jar.waitForExistence(timeout: 8))
        saveNewPage()
        waitForTheFold(jar)
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(jar.waitForExistence(timeout: 5))
        assertLandedOnce(jar, within: 4, "back from the background, it is in")
    }

    /// Under Reduce Motion the page cross-fades to its star, which fades
    /// into the header jar (0.5 s): the star lands once.
    func testUnderReduceMotionASaveFadesItsStarIn() {
        relaunch(["-REDUCE_MOTION"])
        let jar = app.buttons["home.starJar"]
        XCTAssertTrue(jar.waitForExistence(timeout: 8))
        XCTAssertEqual(jar.value as? String, "0")
        saveNewPage()
        assertLandedOnce(jar, within: 5, "the fade lands it")
    }
}
