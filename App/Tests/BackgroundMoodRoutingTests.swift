import XCTest
@testable import MiraNote
@testable import MiraNoteKit

/// The Background tool's moods are plain Mira asks. Each sentence has to
/// route as a background request -- on a blank page and on a page with
/// words and a photo, where image and polish cues compete for it.
@MainActor
final class BackgroundMoodRoutingTests: XCTestCase {
    private func assertEveryMoodSetsTheBackground(on editor: CanvasViewModel, page: String) {
        for mood in BackgroundPanel.moods {
            let ask = BackgroundPanel.ask(for: mood)
            let intent = MiraIntent.classify(ask, editor: editor)
            guard case .setBackground = intent else {
                return XCTFail("\(page): \"\(ask)\" routed to \(intent), not setBackground")
            }
        }
    }

    func testMoodsRouteToBackgroundOnABlankPage() {
        assertEveryMoodSetsTheBackground(on: CanvasViewModel(memory: Memory()), page: "blank")
    }

    func testMoodsRouteToBackgroundOnAFilledPage() {
        let editor = CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
        assertEveryMoodSetsTheBackground(on: editor, page: "starter draft")
    }
}
