import XCTest
@testable import MiraNote
@testable import MiraNoteKit

/// The Background tool's pure pieces (handoff screen 05): the hex field's
/// reading of what was typed, and the CSS band gradients of the set cards.
@MainActor
final class BackgroundToolTests: XCTestCase {
    func testHexFieldAcceptsSixHexDigitsWithOrWithoutHash() {
        XCTAssertEqual(BackgroundToolSheet.normalizedHex("e5d9f0"), "#E5D9F0")
        XCTAssertEqual(BackgroundToolSheet.normalizedHex(" #E5D9F0 "), "#E5D9F0")
        XCTAssertEqual(BackgroundToolSheet.normalizedHex("#a1B2c3"), "#A1B2C3")
    }

    func testHexFieldRejectsAnythingElse() {
        for typed in ["", "#", "E5D9F", "#E5D9F00", "GGGGGG", "#E5 D9F0", "lilac"] {
            XCTAssertNil(BackgroundToolSheet.normalizedHex(typed), "\"\(typed)\" is not a color")
        }
    }

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
            XCTAssertNotNil(UIImage(named: "curated.\(set.id)"), "\(set.id) has its photo")
            let look = CuratedSetLook.look(for: set)
            XCTAssertFalse(look.displayLabel.isEmpty)
            XCTAssertFalse(look.bodyLabel.isEmpty)
        }
    }
}
