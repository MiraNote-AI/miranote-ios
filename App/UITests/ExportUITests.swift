import XCTest

/// Handoff screens 37 and 38: the export sheet sits over the page in the
/// scene, its choices drive the save, and a save ends in a toast that says
/// where the page went -- or, failing, keeps the sheet up to try again.
final class ExportUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDownWithError() throws {
        app = nil
    }

    private func openExport(_ extraArguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"] + extraArguments
        app.launch()
        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.Lunch by the river"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        cover.tap()
        app.buttons["reading.share"].tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    }

    private var sheet: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "export.sheet").firstMatch
    }

    private var toast: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "export.toast").firstMatch
    }

    // The sheet is part of the scene, not a system sheet: it rests on the
    // bottom of the screen over the live page, at the chrome inset -- its
    // content 21 in from a 16 pt inset, the actions' foot 11 above the
    // sheet's, which is 42 above the screen edge.
    func testTheSheetSitsOverThePage() {
        openExport()
        let window = app.windows.firstMatch.frame
        let title = app.staticTexts["Export & Save"]
        XCTAssertEqual(title.frame.minX - window.minX, 16 + 21, accuracy: 1)
        let photos = app.buttons["export.photos"].frame
        XCTAssertEqual(photos.minX - window.minX, 16 + 21, accuracy: 1)
        XCTAssertEqual(window.maxY - photos.maxY, 42 + 11, accuracy: 2)
        // The page's own header stays on screen above the sheet (it is out
        // of VoiceOver's reach while the sheet is up, so its frame is not
        // queried here).
        XCTAssertGreaterThan(sheet.frame.minY - window.minY, 200, "the sheet leaves the page's header clear")
        let share = app.buttons["export.share"].frame
        XCTAssertGreaterThanOrEqual(min(share.width, share.height), 44, "Share is 44 pt to the finger")
    }

    // Choose JPG at Original, save to Photos: the sheet closes and the
    // toast says where the page went.
    func testSavingToPhotosShowsTheSavedToast() {
        openExport()
        app.buttons["export.format.jpg"].tap()
        app.buttons["export.quality.original"].tap()
        XCTAssertTrue(app.buttons["export.format.jpg"].isSelected)
        XCTAssertTrue(app.buttons["export.quality.original"].isSelected)

        let photos = app.buttons["export.photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        waitUntil(photos, "isEnabled == true")
        photos.tap()

        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.label, "Saved to Photos")
        // Let the sheet's exit settle: the toast only stays two seconds.
        Thread.sleep(forTimeInterval: 0.5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "saved toast"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertFalse(sheet.exists, "a saved page closes the sheet")

        waitUntil(toast, "exists == false", timeout: 5)
    }

    // A refused save keeps the sheet up, with the failure toast above it.
    func testAFailedSaveKeepsTheSheetAndSaysSo() {
        openExport(["-PHOTOS-DENIED"])
        let photos = app.buttons["export.photos"]
        waitUntil(photos, "isEnabled == true")
        photos.tap()

        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.label, "Couldn't save -- allow Photos access in Settings.", "the toast names the remedy")
        XCTAssertTrue(sheet.exists, "the sheet stays to try again")
        XCTAssertLessThan(toast.frame.maxY, sheet.frame.minY, "the toast sits above the sheet")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "failed toast"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // The in-scene sheet is modal for VoiceOver, as the system sheet it
    // replaced was (the modal trait reads as an alert-like container), and
    // the page behind it leaves the accessibility tree until it closes.
    func testTheSheetIsModalForAssistiveTechnologies() {
        openExport()
        XCTAssertTrue(app.alerts["export.sheet"].exists, "the sheet carries the modal trait")
        XCTAssertFalse(app.staticTexts["June 21 - calm afternoon"].exists, "the page behind is out of reach")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        waitUntil(sheet, "exists == false")
        XCTAssertTrue(app.staticTexts["June 21 - calm afternoon"].waitForExistence(timeout: 5), "and back once it closes")
    }

    // Print sends the A4 pages built off the main actor with the other
    // formats; the button waits for them.
    func testPrintWaitsForItsPagesThenOpensThePrinter() {
        openExport()
        app.buttons["export.format.print"].tap()
        let print = app.buttons["export.print"]
        XCTAssertTrue(print.waitForExistence(timeout: 5))
        waitUntil(print, "isEnabled == true")
        print.tap()
        XCTAssertTrue(app.navigationBars["Options"].waitForExistence(timeout: 8), "the system print sheet")
    }

    // A tap on the page around the sheet closes it, as does Share again.
    func testATapOnThePageClosesTheSheet() {
        openExport()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        waitUntil(sheet, "exists == false")
    }

    private func waitUntil(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, format)
    }
}
