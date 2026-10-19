import MiraNoteKit
import XCTest
@testable import MiraNote

/// The dragged copy is drawn at the element's own size and then tilted: a
/// tilted element's on-screen bounding box is larger, and drawing the copy
/// at that size grew it while dragged (the 8 degree welcome sticker drew
/// about 90 pt instead of 80).
final class LiftedElementTests: XCTestCase {
    func testATiltedElementLiftsAtItsOwnSize() {
        let sticker = CanvasItem(content: .sticker(GeneratedSticker(prompt: "hello", symbolName: "hand.wave")),
                                 position: CGPoint(x: 290, y: 364), size: CGSize(width: 80, height: 80), rotation: 8)
        // The rotated box as measured on screen: 80 * (cos 8 + sin 8).
        let side = 80 * (cos(8 * Double.pi / 180) + sin(8 * Double.pi / 180))
        let measured = CGRect(x: 250 - (side - 80) / 2, y: 500 - (side - 80) / 2, width: side, height: side)
        let lifted = LiftedElement(item: sticker, measured: measured, size: sticker.size, rotation: 8, finger: .zero)
        XCTAssertEqual(lifted.frame.width, 80, accuracy: 0.01)
        XCTAssertEqual(lifted.frame.height, 80, accuracy: 0.01)
        XCTAssertEqual(lifted.frame.midX, measured.midX, accuracy: 0.01, "centred where the element is")
        XCTAssertEqual(lifted.frame.midY, measured.midY, accuracy: 0.01)
        XCTAssertEqual(lifted.rotation, 8)
    }
}
