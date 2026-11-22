import XCTest

/// #236: with limited photo access, photos picked through the system
/// picker while an Editing pick imports queue behind it, as they do behind
/// Add: the tool stays open until the last one lands, then the photo
/// editor opens on the Editing pick. `-SYSTEM_PICKER_STUB` stands in for
/// the out-of-process picker with one canned photo.
final class ImageEditingQueueUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST", "-PHOTOS-LIMITED", "-IMPORT_DELAY", "3000", "-SYSTEM_PICKER_STUB"]
        app.launch()
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        let library = app.buttons["image.library.open"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        XCTAssertTrue(any("image.library.photo.0").waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private var photos: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "element.image")
    }

    private func canvasState() -> [String: Any] {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let data = probe.label.data(using: .utf8) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func waitForPhotos(_ count: Int, timeout: TimeInterval, _ message: String) {
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == \(count)"), object: photos)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: timeout), .completed, message)
    }

    func testASystemPickWhileEditingImportsLandsBeforeTheEditorOpens() {
        any("image.library.photo.0").tap()
        app.buttons["image.library.editing"].tap()
        let system = app.buttons["image.library.system"]
        XCTAssertTrue(system.isHittable, "the system picker stays offered while the pick imports")
        system.tap()

        waitForPhotos(1, timeout: 6, "the Editing pick landed")
        XCTAssertTrue(any("image.library.grid").exists, "the tool stays open for the queued pick")
        XCTAssertFalse(app.buttons["photo.filter.bw"].exists, "the editor waits for the queued pick")

        waitForPhotos(2, timeout: 8, "the queued system pick landed too")
        XCTAssertTrue(app.buttons["photo.filter.bw"].waitForExistence(timeout: 5), "then the editor opens")
        XCTAssertFalse(any("image.library.grid").exists, "and the tool is closed")
        let state = canvasState()
        let first = (state["elements"] as? [[String: Any]] ?? []).first?["id"] as? String
        XCTAssertNotNil(first)
        XCTAssertEqual(state["photoEditing"] as? String, first, "on the Editing pick, not the queued one")
    }
}
