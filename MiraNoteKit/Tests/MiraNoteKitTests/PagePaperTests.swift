import XCTest
@testable import MiraNoteKit

/// Page paper and color (redesign phase B2): a paper kind drawn over the page
/// and a solid page color beside the painted backdrop.
@MainActor
final class PagePaperTests: XCTestCase {
    func testLegacySaveDecodesToBlankDefaultPage() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000002","title":"old page",
         "body":"","createdAt":700000000,"memoryDate":700000000,"items":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let memory = try decoder.decode(Memory.self, from: Data(legacy.utf8))
        XCTAssertEqual(memory.paper, .blank)
        XCTAssertEqual(memory.pageColorName, "", "old pages keep the default backdrop")
    }

    func testPaperAndColorSurviveARoundTrip() throws {
        var memory = Memory(title: "grid page")
        memory.paper = .grid
        memory.pageColorName = "#E5D9F0"
        let back = try JSONDecoder().decode(Memory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(back.paper, .grid)
        XCTAssertEqual(back.pageColorName, "#E5D9F0")
    }

    func testSetPaperIsOneUndo() {
        let editor = CanvasViewModel(memory: Memory())
        editor.setPaper(.dot)
        XCTAssertEqual(editor.memory.paper, .dot)
        editor.undo()
        XCTAssertEqual(editor.memory.paper, .blank)
    }

    func testAPageColorReplacesThePaintedBackdropInOneUndo() {
        let editor = CanvasViewModel(memory: Memory(backgroundFileName: "dusk.png", backgroundSummary: "a dusk sky"))
        editor.setPageColor("#E5D9F0")
        XCTAssertEqual(editor.memory.pageColorName, "#E5D9F0")
        XCTAssertEqual(editor.memory.backgroundFileName, "", "a color you picked must be visible")
        XCTAssertEqual(editor.memory.backgroundSummary, "")

        editor.undo()
        XCTAssertEqual(editor.memory.pageColorName, "")
        XCTAssertEqual(editor.memory.backgroundFileName, "dusk.png", "undo brings the painting back")
        XCTAssertEqual(editor.memory.backgroundSummary, "a dusk sky")
    }

    func testResetClearsColorAndPaintingTogether() {
        var memory = Memory(backgroundFileName: "dusk.png")
        memory.pageColorName = "#E5D9F0"
        let editor = CanvasViewModel(memory: memory)
        editor.resetPageBackground()
        XCTAssertEqual(editor.memory.pageColorName, "")
        XCTAssertEqual(editor.memory.backgroundFileName, "")
        editor.undo()
        XCTAssertEqual(editor.memory.pageColorName, "#E5D9F0")
        XCTAssertEqual(editor.memory.backgroundFileName, "dusk.png")
    }

    func testAPageColorDragIsOneUndo() {
        let editor = CanvasViewModel(memory: Memory())
        editor.setPageColor("#111111")
        editor.setPageColor("#222222", recordingUndo: false)
        editor.setPageColor("#333333", recordingUndo: false)
        XCTAssertEqual(editor.memory.pageColorName, "#333333")
        editor.undo()
        XCTAssertEqual(editor.memory.pageColorName, "", "one undo removes the whole drag")
    }

    func testNoChangeCallsBurnNoUndo() {
        let editor = CanvasViewModel(memory: Memory())
        editor.setPaper(.blank)
        editor.setPageColor("")
        editor.resetPageBackground()
        XCTAssertFalse(editor.canUndo)
    }
}
