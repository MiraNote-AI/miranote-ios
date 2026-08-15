import UIKit
import XCTest
@testable import MiraNote

/// `aspectBox` decides the canvas box for a photo. A saved original must
/// come back the shape it went in (never center-cropped), so the box aspect
/// tracks the photo's -- clamped so extremes stay bounded on the page.
final class CanvasImageAspectTests: XCTestCase {
    private func image(_ width: CGFloat, _ height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { _ in }
    }

    func testPortraitBoxKeepsPhotoAspect() {
        // 3:4 portrait -> height follows the photo, no crop.
        let box = CanvasImageCache.aspectBox(for: image(300, 400))
        XCTAssertEqual(box.width, 170)
        XCTAssertEqual(box.height, 227, accuracy: 1) // 170 * 4/3
    }

    func testLandscapeBoxClampsToFloor() {
        // Very wide photo would give a sliver; height floors at 110.
        let box = CanvasImageCache.aspectBox(for: image(400, 100))
        XCTAssertEqual(box.height, 110)
    }

    func testTallPortraitClampsToCeiling() {
        // Very tall photo caps at 260 so it can't run the page.
        let box = CanvasImageCache.aspectBox(for: image(100, 400))
        XCTAssertEqual(box.height, 260)
    }

    func testZeroWidthFallsBackToDefault() {
        let box = CanvasImageCache.aspectBox(for: image(0, 0))
        XCTAssertEqual(box, CGSize(width: 170, height: 150))
    }
}
