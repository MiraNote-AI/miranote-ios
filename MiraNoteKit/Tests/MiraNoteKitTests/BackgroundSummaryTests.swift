import XCTest
@testable import MiraNoteKit

@MainActor
final class BackgroundSummaryTests: XCTestCase {
    // MARK: The part that must never break -- old saves

    func testASaveWrittenBeforeThisFieldStillDecodes() throws {
        // A real page as the previous build wrote it: no backgroundSummary.
        let json = Data("""
        {"id":"6E165F5B-C411-40B4-A1A7-940E548D0D21",
         "title":"Lunch by the river","body":"",
         "createdAt":770000000,"memoryDate":770000000,
         "items":[],"backgroundFileName":"dusk.png"}
        """.utf8)
        let memory = try JSONDecoder().decode(Memory.self, from: json)
        XCTAssertEqual(memory.backgroundFileName, "dusk.png")
        XCTAssertEqual(memory.backgroundSummary, "", "an old save has no description, not a crash")
    }

    func testANewSaveRoundTrips() throws {
        var memory = Memory(title: "t")
        memory.backgroundFileName = "dusk.png"
        memory.backgroundSummary = "a warm dusk sky over water"
        let decoded = try JSONDecoder().decode(
            Memory.self, from: try JSONEncoder().encode(memory)
        )
        XCTAssertEqual(decoded.backgroundSummary, "a warm dusk sky over water")
    }

    // MARK: Setting it

    func testSettingABackgroundRecordsWhatItShows() {
        let editor = CanvasViewModel(memory: Memory())
        editor.setBackground(fileName: "dusk.png", describes: "a warm dusk sky")
        XCTAssertEqual(editor.memory.backgroundSummary, "a warm dusk sky")
    }

    func testClearingABackgroundForgetsItsDescription() {
        let editor = CanvasViewModel(memory: Memory())
        editor.setBackground(fileName: "dusk.png", describes: "a warm dusk sky")
        editor.setBackground(fileName: "")
        XCTAssertTrue(editor.memory.backgroundSummary.isEmpty)
    }

    func testUndoRestoresTheDescriptionToo() {
        let editor = CanvasViewModel(memory: Memory())
        editor.setBackground(fileName: "dusk.png", describes: "a warm dusk sky")
        editor.setBackground(fileName: "")
        editor.undo()
        XCTAssertEqual(editor.memory.backgroundFileName, "dusk.png")
        XCTAssertEqual(editor.memory.backgroundSummary, "a warm dusk sky",
                       "undo must restore the pair, not half of it")
    }

    // MARK: What Mira reads

    func testTheMapTellsMiraWhatTheBackdropShows() {
        var memory = Memory()
        memory.backgroundFileName = "dusk.png"
        memory.backgroundSummary = "a warm dusk sky over water"
        let (map, _) = PageMap.build(from: memory, canvasWidth: MiraNoteConfig.pageWidth)
        XCTAssertEqual(map.background, "a warm dusk sky over water")
    }

    func testAnUndescribedBackdropStillSaysThereIsOne() {
        var memory = Memory()
        memory.backgroundFileName = "picked.png"
        let (map, _) = PageMap.build(from: memory, canvasWidth: MiraNoteConfig.pageWidth)
        XCTAssertEqual(map.background, "a picked backdrop image")
    }

    func testNoBackdropIsTheDefaultGradient() {
        let (map, _) = PageMap.build(from: Memory(), canvasWidth: MiraNoteConfig.pageWidth)
        XCTAssertEqual(map.background, "default gradient")
    }

    // Mira picks text colors against this: a solid color must not read as
    // the dark default gradient. The paper ruling rides along.
    func testAPageColorAndPaperAreDescribed() {
        let memory = Memory(paper: .lined, pageColorName: "#E5D9F0")
        let (map, _) = PageMap.build(from: memory, canvasWidth: MiraNoteConfig.pageWidth)
        XCTAssertEqual(map.background, "solid #E5D9F0, lined paper")
    }

    func testPaperAloneIsDescribedOnTheDefaultGradient() {
        let memory = Memory(paper: .dot)
        let (map, _) = PageMap.build(from: memory, canvasWidth: MiraNoteConfig.pageWidth)
        XCTAssertEqual(map.background, "default gradient, dot paper")
    }

    func testPickingAGeneratedBackdropRecordsThePromptItCameFrom() {
        let store = ImageFileStore()
        let editor = CanvasViewModel(memory: Memory())
        let mira = MiraCanvasCoordinator(
            text: ScriptedText(), chat: ScriptedChat(),
            workingDelay: .milliseconds(1), timeout: .seconds(5),
            receiptDismiss: .seconds(60),
            imageStudio: MockImageStudioService(), imageStore: store
        )
        mira.phase = .imageChoices(
            [MockImageStudioService.tinyPNG, MockImageStudioService.tinyPNG],
            prompt: "a warm dusk sky over water",
            placement: .background
        )

        mira.placeImageChoice(0, editor: editor)

        XCTAssertFalse(editor.memory.backgroundFileName.isEmpty)
        XCTAssertEqual(editor.memory.backgroundSummary, "a warm dusk sky over water")
        let (map, _) = PageMap.build(from: editor.memory, canvasWidth: MiraNoteConfig.pageWidth)
        XCTAssertEqual(map.background, "a warm dusk sky over water",
                       "Mira reads what she painted without looking again")
    }
}
