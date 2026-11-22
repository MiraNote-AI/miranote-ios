import XCTest

/// #236: a photo favorite placed from the Sticker panel lands on a free
/// spot of the page in view, as stickers do -- on a page longer than the
/// screen, never below the content, out of sight.
final class ImageFavoriteLandingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private var photos: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "element.image")
    }

    private var favorites: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.item.'"))
    }

    /// The page in view: under the header, above the tool bar.
    private func inView(_ frame: CGRect) -> Bool {
        frame.minY >= app.buttons["nav.trailing"].frame.maxY && frame.maxY <= app.buttons["mode.text"].frame.minY
    }

    private var photosInView: [XCUIElement] {
        photos.allElementsBoundByIndex.filter { inView($0.frame) }
    }

    func testAPhotoFavoriteLandsInViewOnAScrolledLongPage() {
        // Two sample photos at the top of the page; the tall one is saved.
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "the Image tool closed on them")
        sleep(1)
        let tall = photos.allElementsBoundByIndex.first { $0.frame.height > $0.frame.width * 1.2 }
        guard let tall else { return XCTFail("one of the sample photos is tall") }
        tall.press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["Favorite"].waitForExistence(timeout: 5))
        app.buttons["Favorite"].tap()
        sleep(1)

        // A tall block makes the page longer than the screen. No blank
        // lines: since #188 a blank line splits the block.
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Top line" + String(repeating: "\n.", count: 60) + "\nBottom line")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["keyboard.done"].waitForNonExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)).tap()

        // Writing follows the caret down the block, and the page may stay
        // there: drag it back down until the photos are in view again.
        sleep(1)
        for _ in 0..<12 where photosInView.isEmpty {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.3))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.8)))
        }
        sleep(1)
        let header = app.buttons["nav.trailing"].frame.maxY
        XCTAssertFalse(photosInView.isEmpty, "the page is back up, the photos in view")

        // Then down just past the photos, the page's foot still below: slow
        // drags, held at the end, so no fling runs to the foot.
        for _ in 0..<8 where photos.allElementsBoundByIndex.contains(where: { $0.frame.maxY > header }) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.7))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.3)),
                       withVelocity: 300, thenHoldForDuration: 0.3)
        }
        sleep(1)
        let block = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Top line'")).firstMatch
        XCTAssertTrue(block.exists)
        XCTAssertGreaterThan(block.frame.maxY, app.buttons["mode.text"].frame.minY, "the page runs on below")
        XCTAssertEqual(photosInView.count, 0, "the photos are scrolled away above")

        app.buttons["mode.sticker"].tap()
        let tab = app.buttons["sticker.tab.favorites"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
        XCTAssertTrue(favorites.firstMatch.waitForExistence(timeout: 5))
        favorites.firstMatch.tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "back on the canvas")
        sleep(1)

        XCTAssertEqual(photos.count, 3, "the favorite landed")
        XCTAssertEqual(photosInView.count, 1, "in the page in view")
    }
}
