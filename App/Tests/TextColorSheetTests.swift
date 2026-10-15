import MiraNoteKit
import XCTest
@testable import MiraNote

/// The custom color sheet while writing (screens 14 and 20): Apply puts
/// the shown color on the block -- unless it is the block's own color,
/// which stays as it is named and costs no undo step.
final class TextColorSheetTests: XCTestCase {
    private func request(_ target: ColorRequest.Target, block: TextBlock, initial name: String) -> ColorRequest {
        ColorRequest(
            target: target,
            original: CanvasItem(content: .text(block), position: .zero),
            initial: RGBColor(Palette.color(named: name))
        )
    }

    func testApplyingTheTextsOwnColorChangesNothing() {
        let sheet = request(.text, block: TextBlock(text: "Lunch", colorName: "ink"), initial: "ink")
        XCTAssertNil(sheet.applied(sheet.initial.hex), "\"ink\" is not turned into a hex value")
    }

    func testApplyingAnotherTextColorAppliesIt() {
        let sheet = request(.text, block: TextBlock(text: "Lunch", colorName: "ink"), initial: "ink")
        XCTAssertEqual(sheet.applied("#8B5962"), "#8B5962")
    }

    func testABackgroundSheetOpenedWithNoneStillAppliesItsShownColor() {
        let sheet = request(.background, block: TextBlock(text: "Lunch"), initial: "#8B5962")
        XCTAssertEqual(sheet.applied(sheet.initial.hex), sheet.initial.hex, "the color shown is the one applied")
    }

    func testApplyingTheBackgroundsOwnColorChangesNothing() {
        let sheet = request(.background, block: TextBlock(text: "Lunch", backgroundColorName: "#D1E0F0"),
                            initial: "#D1E0F0")
        XCTAssertNil(sheet.applied(sheet.initial.hex))
    }
}
