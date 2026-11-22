import XCTest

/// What a Save does to the star jar (#206): an edited page's star shows
/// its new face at once, and a never-saved draft's first Save flies in.
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
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("draft me a noodle page")
        app.buttons["quick.send"].tap()
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
}
