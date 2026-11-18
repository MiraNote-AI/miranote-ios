import XCTest

/// The Sticker panel's grids, three across (#205, five before): the sets
/// and Favorites share the same columns, and a cell takes taps in its own
/// square only.
final class StickerGridUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.sticker"].waitForExistence(timeout: 5))
        app.buttons["mode.sticker"].tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private var stickers: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "element.sticker")
    }

    private var photos: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "element.image")
    }

    private var favorites: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.item.'"))
    }

    /// Makes a coffee cup and saves it to Favorites; it then waits on Make.
    private func favoriteAMadeSticker() {
        let prompt = app.textFields["sticker.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("a coffee cup")
        app.buttons["sticker.generate.run"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sticker.result.0").firstMatch
            .waitForExistence(timeout: 8))
        app.buttons["sticker.favorite"].tap()
    }

    /// A photo favorite is drawn filled into 76 x 72: a tall photo runs
    /// about 40 pt past that, hidden but still taking taps, and three
    /// across that reached the cell above it. A tap low on the sticker
    /// there placed the photo.
    func testATapLowOnAFavoriteNeverPlacesTheTallPhotoUnderIt() {
        app.buttons["nav.leading"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 5))
        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        sleep(1)
        let tall = photos.allElementsBoundByIndex.first { $0.frame.height > $0.frame.width * 1.2 }
        guard let tall else { return XCTFail("one of the sample photos is tall") }
        // Saved three times, the oldest three: the photo ends up in the
        // second row, under the sticker saved after it.
        for _ in 0..<3 {
            tall.press(forDuration: 0.9)
            XCTAssertTrue(app.buttons["Favorite"].waitForExistence(timeout: 5))
            app.buttons["Favorite"].tap()
            sleep(1)
        }
        app.buttons["mode.sticker"].tap()
        favoriteAMadeSticker()
        // Cancel lets the made sticker go; its favorite stays.
        app.buttons["nav.leading"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        sleep(1)
        let photosBefore = photos.count

        app.buttons["mode.sticker"].tap()
        XCTAssertTrue(app.buttons["sticker.tab.favorites"].waitForExistence(timeout: 5))
        app.buttons["sticker.tab.favorites"].tap()
        XCTAssertTrue(favorites.element(boundBy: 3).waitForExistence(timeout: 5))
        let sticker = favorites.element(boundBy: 0).frame
        XCTAssertEqual(favorites.element(boundBy: 3).frame.midX, sticker.midX, accuracy: 1,
                       "the photo sits under the sticker")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: sticker.midX, dy: sticker.maxY - 8)).tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5), "back on the canvas")
        XCTAssertTrue(stickers.firstMatch.waitForExistence(timeout: 5), "the sticker landed")
        XCTAssertEqual(photos.count, photosBefore, "not the photo under it")
    }

    /// The Favorites cells stand where the set's do, so a tab change keeps
    /// them in place.
    func testFavoritesLineUpWithTheSetCells() {
        favoriteAMadeSticker()
        app.buttons["sticker.tab.favorites"].tap()
        XCTAssertTrue(favorites.firstMatch.waitForExistence(timeout: 5))
        let favorite = favorites.firstMatch.frame
        app.buttons["sticker.tab.food"].tap()
        let preset = app.buttons["sticker.preset.focaccia"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        XCTAssertEqual(favorite.midX, preset.frame.midX, accuracy: 1, "the first column stays put across the tabs")
    }
}
