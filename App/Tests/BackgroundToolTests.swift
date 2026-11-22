import XCTest
@testable import MiraNote
@testable import MiraNoteKit

/// The Background tool's pure pieces (handoff screen 05): the set cards'
/// CSS band gradients.
@MainActor
final class BackgroundToolTests: XCTestCase {
    /// Stops past the box are cut at its edges, the colors there
    /// interpolated: the band shows what CSS would draw inside the box.
    func testBandStopsAreCutToTheBox() {
        let cut = CSSLinearGradient.clipped([(0xFE6202, 0.5), (0x920201, 1.5)])
        XCTAssertEqual(cut.map(\.1), [0, 0.5, 1])
        XCTAssertEqual(cut[0].0, 0xFE6202, "before the first stop, its color")
        XCTAssertEqual(cut[2].0, 0xC83202, "halfway between the two stops at the edge")
    }

    func testEveryCuratedSetHasACard() {
        for set in CuratedSet.all {
            let look = CuratedSetLook.look(for: set)
            XCTAssertFalse(look.displayLabel.isEmpty)
            if case .image(let name) = look.band {
                XCTAssertNotNil(UIImage(named: name), "\(set.id) has its band")
            }
        }
    }
}
