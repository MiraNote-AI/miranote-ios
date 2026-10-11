import XCTest
@testable import MiraNoteKit

/// Per-block text styling (redesign phase B1): font, alignment and a text
/// background ride on TextBlock; color keeps using `colorName`.
@MainActor
final class TextStyleTests: XCTestCase {
    // MARK: Persistence

    func testLegacyBlockDecodesToTheDefaults() throws {
        let legacy = #"{"text":"old words","pointSize":17,"colorName":"forest"}"#
        let block = try JSONDecoder().decode(TextBlock.self, from: Data(legacy.utf8))
        XCTAssertEqual(block.text, "old words")
        XCTAssertEqual(block.colorName, "forest")
        XCTAssertEqual(block.fontName, "", "no font recorded means the default face")
        XCTAssertEqual(block.alignment, .leading, "old pages were left-aligned")
        XCTAssertEqual(block.backgroundColorName, "", "old pages had no text background")
    }

    func testStyledBlockSurvivesARoundTrip() throws {
        var block = TextBlock(text: "styled", pointSize: 20, colorName: "#E5AC95")
        block.fontName = "Futura"
        block.alignment = .center
        block.backgroundColorName = "#24382D"
        let back = try JSONDecoder().decode(TextBlock.self, from: JSONEncoder().encode(block))
        XCTAssertEqual(back, block)
    }

    // MARK: Editing

    private func editorWithText() -> (CanvasViewModel, CanvasItem.ID) {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("words", at: CGPoint(x: 100, y: 100))
        return (editor, id)
    }

    private func block(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> TextBlock? {
        guard case .text(let block) = editor.item(id)?.content else { return nil }
        return block
    }

    func testFontChangeIsOneUndo() {
        let (editor, id) = editorWithText()
        editor.setTextFont(itemID: id, to: "Futura")
        XCTAssertEqual(block(editor, id)?.fontName, "Futura")
        editor.undo()
        XCTAssertEqual(block(editor, id)?.fontName, "")
    }

    func testAlignmentChangeIsOneUndo() {
        let (editor, id) = editorWithText()
        editor.setTextAlignment(itemID: id, to: .trailing)
        XCTAssertEqual(block(editor, id)?.alignment, .trailing)
        editor.undo()
        XCTAssertEqual(block(editor, id)?.alignment, .leading)
    }

    func testBackgroundChangeIsOneUndo() {
        let (editor, id) = editorWithText()
        editor.setTextBackground(itemID: id, to: "#24382D")
        XCTAssertEqual(block(editor, id)?.backgroundColorName, "#24382D")
        editor.undo()
        XCTAssertEqual(block(editor, id)?.backgroundColorName, "")
    }

    func testSettingTheSameStyleBurnsNoUndo() {
        let (editor, id) = editorWithText()
        let undoableBefore = editor.canUndo
        editor.setTextFont(itemID: id, to: "")
        editor.setTextAlignment(itemID: id, to: .leading)
        editor.setTextBackground(itemID: id, to: "")
        XCTAssertEqual(editor.canUndo, undoableBefore, "no-change calls record no snapshot")
    }

    func testAPickerDragIsOneUndo() {
        let (editor, id) = editorWithText()
        editor.setTextColorName(itemID: id, to: "#111111")
        editor.setTextColorName(itemID: id, to: "#222222", recordingUndo: false)
        editor.setTextColorName(itemID: id, to: "#333333", recordingUndo: false)
        XCTAssertEqual(block(editor, id)?.colorName, "#333333")
        editor.undo()
        XCTAssertEqual(block(editor, id)?.colorName, "ink", "one undo removes the whole drag")
    }

    func testAlignmentCyclesLeadingCenterTrailing() {
        XCTAssertEqual(TextAlign.leading.next, .center)
        XCTAssertEqual(TextAlign.center.next, .trailing)
        XCTAssertEqual(TextAlign.trailing.next, .leading)
    }
}
