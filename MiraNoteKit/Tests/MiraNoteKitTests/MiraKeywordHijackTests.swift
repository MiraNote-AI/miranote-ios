import XCTest
@testable import MiraNoteKit

/// The keyword ladder runs before the canvas turn, so any ask that
/// merely MENTIONS a noun it watches for can be claimed by a branch that
/// wants to do something else entirely. These are the asks this feature
/// exists to serve; each must reach the model.
@MainActor
final class MiraKeywordHijackTests: XCTestCase {
    private func board() -> CanvasViewModel {
        let model = CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
        model.canvasWidth = 393
        return model
    }

    private func assertReachesTheModel(_ ask: String, line: UInt = #line) {
        let intent = MiraIntent.classify(ask, editor: board())
        guard case .canvasTurn = intent else {
            return XCTFail(
                "\"\(ask)\" was claimed by the keyword ladder: \(intent)",
                line: line
            )
        }
    }

    // Geometry asks that happen to name the thing they act on.
    func testMoveThePhoto() { assertReachesTheModel("move the photo up a bit") }
    func testLayerThePhoto() { assertReachesTheModel("put the photo behind everything else") }
    func testResizeThePhoto() { assertReachesTheModel("make the photo bigger") }
    func testAlignThePhoto() { assertReachesTheModel("center the photo") }
    func testMoveTheSticker() { assertReachesTheModel("move the sticker to the corner") }
    func testLayerTheSticker() { assertReachesTheModel("send the sticker to the back") }
    func testMoveTheTitle() { assertReachesTheModel("move the title above the photo") }
    func testResizeTheTitle() { assertReachesTheModel("the title is too small") }
    func testMoveTheText() { assertReachesTheModel("move the text down") }

    // Asks about how the page looks.
    func testHowDoesItLook() { assertReachesTheModel("how does this page look") }
    func testIsItCrowded() { assertReachesTheModel("does this feel crowded") }

    // The keyword ladder must still keep what it is genuinely for.
    func testPolishStillTransformsText() {
        guard case .transformText(_, _, .polish) = MiraIntent.classify("polish this", editor: board())
        else { return XCTFail("polish is a verb the ladder should keep") }
    }

    func testAddATitleStillWritesOne() {
        guard case .addTitle = MiraIntent.classify("add a soft title", editor: board())
        else { return XCTFail("an add-shaped title ask should still write one") }
    }
}
