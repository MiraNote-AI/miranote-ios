import XCTest

/// Mira image and style asks (deterministic under -UITEST: the mock
/// studio answers instantly with two tiny candidates).
final class MiraImageAskUITests: XCTestCase {
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

    private func startMemory() {
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    private func ask(_ words: String) {
        let input = app.textFields["mira.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(words)
        app.buttons["mira.go"].tap()
    }

    /// Samples land two photos; tap empty paper BELOW BOTH so nothing is
    /// selected (the photos stagger down the page -- a fixed offset from
    /// the first one can land on the second).
    private func addSamplePhotos() {
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        let second = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
            .withOffset(CGVector(dx: 0, dy: 120)).tap()
    }

    // "draw ..." -> two candidates on the card; tapping one places it.
    func testDrawYieldsChoicesAndTapPlaces() {
        startMemory()
        ask("draw a paper crane")

        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "two candidates arrive")
        XCTAssertTrue(app.buttons["mira.imageChoice.1"].exists)
        first.tap()

        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 5))
        let placed = app.descendants(matching: .any)
            .matching(identifier: "element.image").firstMatch
        XCTAssertTrue(placed.waitForExistence(timeout: 5), "the pick landed on the canvas")
    }

    // A filter ask on a selected photo is instant: receipt, no working bar.
    func testFilterAskIsInstantWithReceipt() {
        startMemory()
        addSamplePhotos()
        let photo = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 0)
        photo.tap()

        ask("make the photo black and white")
        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 5))
    }

    // Two photos, nothing selected: Mira asks which one, canvas untouched.
    func testAmbiguousPhotoAsksToTapOne() {
        startMemory()
        addSamplePhotos()

        ask("make the photo black and white")
        XCTAssertTrue(
            app.staticTexts["More than one photo here -- tap the one you mean and ask again."]
                .waitForExistence(timeout: 8),
            "the clarify card names the fix"
        )
    }
}
