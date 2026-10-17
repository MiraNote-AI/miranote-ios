import MiraNoteKit
import UIKit
import XCTest
@testable import MiraNote

/// The canvas draws a decoded display copy of a photo, never the camera
/// original (owner, TestFlight 1.0(5): photo drags stuttered); export and
/// Reading still get the original pixels.
@MainActor
final class DisplayImageTests: XCTestCase {
    private func bigPhoto() throws -> String {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000), format: format)
            .jpegData(withCompressionQuality: 0.8) { context in
                UIColor.orange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
            }
        return try ImageFileStore().save(data, id: UUID())
    }

    func testTheCanvasDrawsABoundedDecodedCopyOnce() throws {
        let name = try bigPhoto()
        let store = ImageFileStore()
        let decodes = RenderCounters.displayImageDecodes
        let shown = try XCTUnwrap(CanvasImageCache.image(fileName: name, filterName: "", store: store,
                                                         maxPixels: CanvasImageCache.displayPixels))
        let pixels = max(shown.size.width * shown.scale, shown.size.height * shown.scale)
        XCTAssertLessThanOrEqual(pixels, CanvasImageCache.displayPixels, "the canvas draws the 12 MP original")
        XCTAssertEqual(pixels, CanvasImageCache.displayPixels, accuracy: 1, "and not smaller than the display copy")

        let again = CanvasImageCache.image(fileName: name, filterName: "", store: store,
                                           maxPixels: CanvasImageCache.displayPixels)
        XCTAssertTrue(again === shown, "decoded again for the next frame")
        XCTAssertEqual(RenderCounters.displayImageDecodes, decodes + 1)

        let original = try XCTUnwrap(CanvasImageCache.image(fileName: name, filterName: "", store: store))
        XCTAssertEqual(original.size.width * original.scale, 4000, "export lost the original pixels")
    }
}
