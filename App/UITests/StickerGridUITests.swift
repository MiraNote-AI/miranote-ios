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
        app.buttons["mode.sticker"].tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "the Image tool closed on them")
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
        XCTAssertEqual(app.buttons["nav.leading"].label, "Cancel")
        app.buttons["nav.leading"].tap()
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.miraComposer.waitForExistence(timeout: 5), "back on the canvas")
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

    func testASetShowsThreeAcrossAndScrollsToItsLastRow() {
        let food = app.buttons["sticker.tab.food"]
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        food.tap()
        let first = ["focaccia", "burrito", "hotpot", "martini"].map { app.buttons["sticker.preset.\($0)"] }
        XCTAssertTrue(first[0].waitForExistence(timeout: 5))
        let row = first[0...2].map(\.frame)
        for frame in row {
            XCTAssertEqual(frame.midY, row[0].midY, accuracy: 1, "the first three share a row")
        }
        XCTAssertGreaterThan(first[3].frame.minY, row[0].maxY, "the fourth starts the next row")
        XCTAssertEqual(first[3].frame.midX, row[0].midX, accuracy: 1, "under the first")
        XCTAssertLessThanOrEqual(row[2].maxX, app.frame.maxX - 16, "the third stays inside the sheet")

        // The last row (pancake, ice cream, bao): drag the grid up from
        // inside the sheet.
        let bao = app.buttons["sticker.preset.bao"]
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let from = origin.withOffset(CGVector(dx: app.frame.midX, dy: food.frame.maxY + 230))
        let to = origin.withOffset(CGVector(dx: app.frame.midX, dy: food.frame.maxY + 40))
        for _ in 0..<8 where !(bao.exists && bao.isHittable) {
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        XCTAssertTrue(bao.exists && bao.isHittable, "the set scrolls down to its last row")
    }
}
