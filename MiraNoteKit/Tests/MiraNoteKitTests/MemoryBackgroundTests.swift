import XCTest
@testable import MiraNoteKit

@MainActor
final class MemoryBackgroundTests: XCTestCase {
    func testLegacySaveWithoutFieldDecodesToEmpty() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","title":"old page",
         "body":"","createdAt":700000000,"memoryDate":700000000,"items":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let memory = try decoder.decode(Memory.self, from: Data(legacy.utf8))
        XCTAssertEqual(memory.backgroundFileName, "", "old saves mean no background")
    }

    func testBackgroundSurvivesARoundTrip() throws {
        var memory = Memory(title: "trip")
        memory.backgroundFileName = "bg.png"
        let data = try JSONEncoder().encode(memory)
        let back = try JSONDecoder().decode(Memory.self, from: data)
        XCTAssertEqual(back.backgroundFileName, "bg.png")
    }

    func testSetBackgroundIsOneUndo() {
        let editor = CanvasViewModel(memory: Memory())
        editor.setBackground(fileName: "bg.png")
        XCTAssertEqual(editor.memory.backgroundFileName, "bg.png")
        XCTAssertTrue(editor.canUndo)
        editor.undo()
        XCTAssertEqual(editor.memory.backgroundFileName, "", "one undo clears it back")
    }

    func testClearingAnAlreadyDefaultPageBurnsNoUndo() {
        let editor = CanvasViewModel(memory: Memory())
        editor.setBackground(fileName: "")
        XCTAssertFalse(editor.canUndo, "a no-change call records no snapshot")
    }

    func testClearViaEmptyFileName() {
        let editor = CanvasViewModel(memory: Memory(backgroundFileName: "bg.png"))
        editor.setBackground(fileName: "")
        XCTAssertEqual(editor.memory.backgroundFileName, "")
        editor.undo()
        XCTAssertEqual(editor.memory.backgroundFileName, "bg.png")
    }
}
