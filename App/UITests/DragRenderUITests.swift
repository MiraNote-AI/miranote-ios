import XCTest

/// Owner, TestFlight 1.0(5): dragging a photo was not smooth. A drag must
/// be cheap per frame: no photo decoded again, and the canvas scene (the
/// header, the dock, the tools, every element) not re-rendered for every
/// finger move. Read from the -UITEST probe's render counters.
final class DragRenderUITests: XCTestCase {
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

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func canvasState() -> [String: Any] {
        let probe = app.descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let data = probe.label.data(using: .utf8) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func testDraggingAPhotoRendersNoMoreThanItMoves() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        app.buttons["image.library.open"].tap()
        XCTAssertTrue(any("image.library.photo.0").waitForExistence(timeout: 5))
        any("image.library.photo.0").tap()
        any("image.library.photo.1").tap()
        app.buttons["image.composer.add"].tap()
        app.buttons["nav.trailing"].tap()
        let photo = app.descendants(matching: .any).matching(identifier: "element.image").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        // Let the probe settle after placing.
        Thread.sleep(forTimeInterval: 1)
        let before = canvasState()

        let start = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 40, dy: 180)),
                    withVelocity: 120, thenHoldForDuration: 0.4)
        Thread.sleep(forTimeInterval: 0.8)
        let after = canvasState()

        let bodies = (after["sceneBodies"] as? Int ?? 0) - (before["sceneBodies"] as? Int ?? 0)
        let decodes = (after["imageDecodes"] as? Int ?? 0) - (before["imageDecodes"] as? Int ?? 0)
        XCTAssertEqual(decodes, 0, "a photo was decoded again during the drag")
        // A drag of about 1.5 s runs ~90 frames; a few evaluations at its
        // start and end are fine, one per frame is the jank.
        XCTAssertLessThanOrEqual(bodies, 12, "the canvas scene re-rendered \(bodies) times during one drag")
        let moved = (after["elements"] as? [[String: Any]] ?? []).contains { element in
            (before["elements"] as? [[String: Any]] ?? []).contains {
                $0["id"] as? String == element["id"] as? String && $0["y"] as? Double != element["y"] as? Double
            }
        }
        XCTAssertTrue(moved, "the drag did not move the photo")
    }

    /// The dragged copy is as big as the photo on the card: it must not
    /// shrink while it moves (#127 review: 182 -> 170 pt on 17 Pro).
    func testTheDraggedCopyKeepsThePhotosSize() {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.image"].waitForExistence(timeout: 5))
        app.buttons["mode.image"].tap()
        app.buttons["image.library.open"].tap()
        XCTAssertTrue(any("image.library.photo.0").waitForExistence(timeout: 5))
        any("image.library.photo.0").tap()
        app.buttons["image.composer.add"].tap()
        app.buttons["nav.trailing"].tap()
        let photo = app.descendants(matching: .any).matching(identifier: "element.image").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        let width = photo.frame.width
        let element = { (state: [String: Any]) in (state["elements"] as? [[String: Any]] ?? [])[0] }
        let before = element(canvasState())

        let start = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 60)),
                    withVelocity: 120, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 0.6)
        let state = canvasState()
        let lifted = state["liftedWidth"] as? Double ?? 0
        XCTAssertEqual(lifted, Double(width), accuracy: 1, "the copy is drawn at the photo's size on the card")

        // 60 screen points of drag move the photo 60 / scale page points:
        // it lands under the finger.
        let scale = Double(width) / (before["w"] as? Double ?? 1)
        let moved = (element(state)["y"] as? Double ?? 0) - (before["y"] as? Double ?? 0)
        XCTAssertGreaterThan(scale, 1.02, "the card is scaled up on this phone")
        XCTAssertEqual(moved * scale, 60, accuracy: 3, "moved \(moved) page points at scale \(scale)")
    }
}
