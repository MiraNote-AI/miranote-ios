import XCTest

/// What a Save does to the star jar (#206): an edited page's star shows
/// its new face at once.
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
        app.buttons["mode.background"].tap()
        let lilac = app.buttons["background.color.#E6D9F0"]
        XCTAssertTrue(lilac.waitForExistence(timeout: 5))
        lilac.tap()
        app.buttons["mode.background"].tap()
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
}
