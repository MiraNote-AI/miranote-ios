import XCTest
@testable import MiraNoteKit

/// Curated sets (handoff screen 05): one tap dresses the page -- display
/// face, body face, text color and page color -- as one undo step.
@MainActor
final class CuratedSetTests: XCTestCase {
    private let didot = CuratedSet.all[1]

    private func block(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> TextBlock? {
        guard case .text(let block) = editor.item(id)?.content else { return nil }
        return block
    }

    func testTheHandoffDrawsEightSets() {
        XCTAssertEqual(CuratedSet.all.count, 8)
        XCTAssertEqual(Set(CuratedSet.all.map(\.id)).count, 8, "ids are unique")
        for set in CuratedSet.all {
            XCTAssertEqual(set.textColor.count, 7, "\(set.id) text color is #RRGGBB")
            XCTAssertEqual(set.pageColor.count, 7, "\(set.id) page color is #RRGGBB")
        }
    }

    func testASetDressesTitlesBodyTextAndThePage() {
        let editor = CanvasViewModel(memory: Memory())
        let title = editor.addText("Lunch by the river", at: CGPoint(x: 100, y: 60), pointSize: 30)
        let body = editor.addText("noodles and sun", at: CGPoint(x: 100, y: 160), pointSize: 17)

        editor.applyCuratedSet(didot)

        XCTAssertEqual(block(editor, title)?.fontName, "Didot")
        XCTAssertEqual(block(editor, body)?.fontName, "Cardo")
        XCTAssertEqual(block(editor, title)?.colorName, "#2D372C")
        XCTAssertEqual(block(editor, body)?.colorName, "#2D372C")
        XCTAssertEqual(editor.memory.pageColorName, "#FCD766")
        XCTAssertEqual(editor.wornCuratedSet(), didot)
    }

    func testTheWholeSetIsOneUndo() {
        let editor = CanvasViewModel(memory: Memory())
        let title = editor.addText("title", at: CGPoint(x: 100, y: 60), pointSize: 30)
        let body = editor.addText("body", at: CGPoint(x: 100, y: 160), pointSize: 17)
        editor.setTextFont(itemID: body, to: "Futura")
        editor.setPageColor("#F6F4E8")
        let titleBefore = block(editor, title)

        editor.applyCuratedSet(didot)
        editor.undo()

        XCTAssertEqual(block(editor, title), titleBefore)
        XCTAssertEqual(block(editor, body)?.fontName, "Futura")
        XCTAssertEqual(editor.memory.pageColorName, "#F6F4E8")
        XCTAssertNil(editor.wornCuratedSet())
    }

    func testASetOnAPageWithoutWordsStillColorsThePage() {
        let editor = CanvasViewModel(memory: Memory())
        editor.applyCuratedSet(CuratedSet.all[6])
        XCTAssertEqual(editor.memory.pageColorName, "#24382D")
        XCTAssertTrue(editor.canUndo)
    }

    func testASetReplacesAPaintedBackdrop() {
        let editor = CanvasViewModel(memory: Memory())
        editor.setBackground(fileName: "sunset.png", describes: "a sunset")
        XCTAssertNil(editor.wornCuratedSet(), "a painted page wears no set")

        editor.applyCuratedSet(didot)
        XCTAssertEqual(editor.memory.backgroundFileName, "")
        XCTAssertEqual(editor.memory.backgroundSummary, "")
        XCTAssertEqual(editor.wornCuratedSet(), didot)
    }

    func testASetThePageAlreadyWearsRecordsNoUndo() {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText("body", at: CGPoint(x: 100, y: 160), pointSize: 17)
        editor.applyCuratedSet(didot)
        let count = editor.changeCount

        editor.applyCuratedSet(didot)
        XCTAssertEqual(editor.changeCount, count)
    }

    // Sets 04 and 08 share their faces; only the page color tells them
    // apart, so the page wears exactly the one tapped.
    func testTwinFacedSetsAreToldApartByThePage() {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText("a quiet afternoon", at: CGPoint(x: 100, y: 160), pointSize: 17)
        let rose = CuratedSet.all[7]

        editor.applyCuratedSet(rose)
        XCTAssertEqual(editor.wornCuratedSet(), rose)

        editor.setPageColor(CuratedSet.all[3].pageColor)
        XCTAssertNil(editor.wornCuratedSet(), "set 04 also wants its own text color")
    }
}
