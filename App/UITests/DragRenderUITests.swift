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

    /// While a long press is held the photo stays at its size and place on
    /// the card until the menu opens (#132: the press preview drew it
    /// without the card's scale, 182 -> 172 pt and 15 pt lower on 17 Pro).
    /// Read from a screenshot taken mid-press: the sample photo is one flat
    /// red.
    func testAPressedPhotoKeepsItsSizeAndPlace() {
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
        let card = photo.frame
        XCTAssertEqual(redBox(in: XCUIScreen.main.screenshot(), around: card)?.width ?? 0, card.width,
                       accuracy: 2, "the photo reads at rest")

        // The press blocks this thread: the shot is taken beside it, after
        // the touch is down and before the menu opens (about 0.7 s).
        var pressed: XCUIScreenshot?
        let shot = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            pressed = XCUIScreen.main.screenshot()
            shot.signal()
        }
        photo.press(forDuration: 1.2)
        shot.wait()
        let box = pressed.flatMap { redBox(in: $0, around: card) } ?? .zero
        // Never smaller; the system's own lift grows it a few percent about
        // its centre just before the menu opens.
        XCTAssertGreaterThan(box.width, card.width - 2, "pressed \(box), on the card \(card)")
        XCTAssertLessThan(box.width, card.width * 1.05, "pressed \(box), on the card \(card)")
        XCTAssertEqual(box.midX, card.midX, accuracy: 2, "pressed \(box), on the card \(card)")
        XCTAssertEqual(box.midY, card.midY, accuracy: 2, "pressed \(box), on the card \(card)")
    }

    /// The bounding box, in points, of the sample photo's red within 40 pt
    /// of `frame` (the page's gradient below reads red-ish too).
    private func redBox(in shot: XCUIScreenshot, around frame: CGRect) -> CGRect? {
        guard let image = shot.image.cgImage else { return nil }
        let scale = CGFloat(image.width) / shot.image.size.width
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let area = frame.insetBy(dx: -40, dy: -40)
        var box: CGRect?
        for y in max(0, Int(area.minY * scale))..<min(height, Int(area.maxY * scale)) {
            for x in max(0, Int(area.minX * scale))..<min(width, Int(area.maxX * scale)) {
                let i = (y * width + x) * 4
                guard pixels[i] > 120, pixels[i + 1] < 90, pixels[i + 2] < 90 else { continue }
                let point = CGRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale, width: 1 / scale, height: 1 / scale)
                box = box?.union(point) ?? point
            }
        }
        return box
    }
}
