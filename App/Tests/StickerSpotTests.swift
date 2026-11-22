import MiraNoteKit
import XCTest
@testable import MiraNote

/// Add's free-spot search: the middle of the page in view, or the nearest
/// spot clear of every element.
final class StickerSpotTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 400, width: 360, height: 500)

    private func block(at center: CGPoint, size: CGSize) -> CanvasItem {
        CanvasItem(content: .text(TextBlock(text: "words")), position: center, size: size)
    }

    private func box(at spot: CGPoint) -> CGRect {
        let side = StickerSpot.side
        return CGRect(x: spot.x - side / 2, y: spot.y - side / 2, width: side, height: side)
    }

    func testAnEmptyPageGivesTheMiddle() {
        let spot = StickerSpot.find(in: visible, avoiding: [])
        XCTAssertEqual(spot.x, visible.midX, accuracy: 4)
        XCTAssertEqual(spot.y, visible.midY, accuracy: 4)
    }

    func testAnElementOverTheMiddleMovesTheSpotClearOfIt() {
        let item = block(at: CGPoint(x: visible.midX, y: visible.midY), size: CGSize(width: 200, height: 120))
        let spot = StickerSpot.find(in: visible, avoiding: [item])
        let taken = CGRect(x: item.position.x - 100, y: item.position.y - 60, width: 200, height: 120)
        XCTAssertFalse(box(at: spot).intersects(taken.insetBy(dx: -8, dy: -8)), "8 pt clear of the element")
        XCTAssertTrue(visible.contains(box(at: spot)), "inside the page in view")
        // The nearest free spot: just above or below the block, not a corner.
        XCTAssertEqual(spot.x, visible.midX, accuracy: 4)
        XCTAssertLessThanOrEqual(abs(spot.y - visible.midY), 60 + 8 + StickerSpot.side / 2 + 8)
    }

    /// A photo's box (#236): the spot keeps the whole box in view and
    /// clear of the element, not only a sticker's 88 pt.
    func testAPhotosBoxStaysInViewAndClear() {
        let size = CGSize(width: 170, height: 130)
        let item = block(at: CGPoint(x: visible.midX, y: visible.midY), size: CGSize(width: 200, height: 120))
        let spot = StickerSpot.find(in: visible, avoiding: [item], size: size)
        let photo = CGRect(x: spot.x - size.width / 2, y: spot.y - size.height / 2,
                           width: size.width, height: size.height)
        let taken = CGRect(x: item.position.x - 100, y: item.position.y - 60, width: 200, height: 120)
        XCTAssertFalse(photo.intersects(taken.insetBy(dx: -8, dy: -8)), "8 pt clear of the element")
        XCTAssertTrue(visible.contains(photo), "the whole photo inside the page in view")
    }

    func testAFullViewFallsBackToTheMiddle() {
        let item = block(at: CGPoint(x: visible.midX, y: visible.midY), size: visible.size)
        let spot = StickerSpot.find(in: visible, avoiding: [item])
        XCTAssertEqual(spot, CGPoint(x: visible.midX, y: visible.midY))
    }
}
