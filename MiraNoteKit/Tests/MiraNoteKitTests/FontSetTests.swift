import XCTest
@testable import MiraNoteKit

/// Curated font sets (handoff screen 05): one tap sets the page's display
/// type and body type together.
@MainActor
final class FontSetTests: XCTestCase {
    private func font(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> String? {
        guard case .text(let block) = editor.item(id)?.content else { return nil }
        return block.fontName
    }

    func testTitlesTakeTheDisplayFaceAndTheRestTheBodyFace() {
        let editor = CanvasViewModel(memory: Memory())
        let title = editor.addText("Lunch by the river", at: CGPoint(x: 100, y: 60), pointSize: 30)
        let body = editor.addText("noodles and sun", at: CGPoint(x: 100, y: 160), pointSize: 17)

        editor.applyFontSet(display: "Didot", body: "Optima")

        XCTAssertEqual(font(editor, title), "Didot")
        XCTAssertEqual(font(editor, body), "Optima")
    }

    func testTheWholeSetIsOneUndo() {
        let editor = CanvasViewModel(memory: Memory())
        let title = editor.addText("title", at: CGPoint(x: 100, y: 60), pointSize: 30)
        let body = editor.addText("body", at: CGPoint(x: 100, y: 160), pointSize: 17)
        editor.setTextFont(itemID: body, to: "Futura")

        editor.applyFontSet(display: "Didot", body: "Optima")
        editor.undo()

        XCTAssertEqual(font(editor, title), "")
        XCTAssertEqual(font(editor, body), "Futura")
    }

    func testASetThatChangesNothingRecordsNoUndo() {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText("body", at: CGPoint(x: 100, y: 160), pointSize: 17)
        editor.applyFontSet(display: "Didot", body: "Optima")
        let count = editor.changeCount

        editor.applyFontSet(display: "Didot", body: "Optima")
        XCTAssertEqual(editor.changeCount, count)

        let blank = CanvasViewModel(memory: Memory())
        blank.applyFontSet(display: "Didot", body: "Optima")
        XCTAssertFalse(blank.canUndo, "a page without text has nothing to set")
    }
}
