import XCTest
@testable import MiraNoteKit

/// The canvas draft (handoff 7.8, acceptance F1-F4).
final class TriggerDraftBuilderTests: XCTestCase {
    private func memory(count: Int, detail: String) -> TriggerMemory {
        let ids = (1...count).map { "P\($0)" }
        let base = TriggerMemoryTests.memory(ids: ids, peak: "P3")
        return TriggerMemory(
            id: "m", date: "2026-10-18", daypart: .afternoon, bucket: "b", push: base.push, story: base.story,
            ending: .init(factLine: "10.18 \u{00B7} Arboretum", detail: detail, question: "What else?",
                          questionId: "A1", ctaLabel: "Keep"),
            facts: ["P1": "a bench", "P3": "the arch"]
        )
    }

    private func files(_ count: Int) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (1...count).map { ("P\($0)", "file-\($0).png") })
    }

    private func texts(_ page: Memory) -> [(block: TextBlock, item: CanvasItem)] {
        page.items.compactMap { item in
            if case .text(let block) = item.content { return (block, item) }
            return nil
        }
    }

    private func images(_ page: Memory) -> [(ref: ImageRef, item: CanvasItem)] {
        page.items.compactMap { item in
            if case .image(let ref) = item.content { return (ref, item) }
            return nil
        }
    }

    func testDraftTitleIsTheTopLargestTextAndEqualsFactLine() throws {
        let page = TriggerDraftBuilder.build(memory: memory(count: 8, detail: "Light on the arch"),
                                             imageFiles: files(8), detailFont: "Lora")
        let all = texts(page)
        let top = try XCTUnwrap(all.min { $0.item.position.y < $1.item.position.y })
        let largest = try XCTUnwrap(all.max { $0.block.pointSize < $1.block.pointSize })
        XCTAssertEqual(top.block.text, "10.18 \u{00B7} Arboretum")
        XCTAssertEqual(top.block.pointSize, 30)
        XCTAssertEqual(largest.block.text, top.block.text)
        XCTAssertEqual(page.title, top.block.text)
        // Every photo sits under the fact line.
        for image in images(page) { XCTAssertGreaterThan(image.item.position.y, top.item.position.y) }
    }

    func testDraftHasEightPhotosWithPeakInBigCell() throws {
        let page = TriggerDraftBuilder.build(memory: memory(count: 8, detail: ""), imageFiles: files(8),
                                             detailFont: "Lora")
        let placed = images(page)
        XCTAssertEqual(placed.count, 8)
        let biggest = try XCTUnwrap(placed.max { $0.item.size.width * $0.item.size.height
            < $1.item.size.width * $1.item.size.height })
        XCTAssertEqual(biggest.ref.fileName, "file-3.png", "the peak takes the big cell")
        let grid = TriggerGridLayout(photoCount: 8, width: MiraNoteConfig.pageWidth - 2 * TriggerDraftBuilder.margin)
        XCTAssertEqual(biggest.item.size, grid.big.size)
        for image in placed {
            XCTAssertGreaterThanOrEqual(image.item.position.x - image.item.size.width / 2, 0)
            XCTAssertLessThanOrEqual(image.item.position.x + image.item.size.width / 2, MiraNoteConfig.pageWidth)
        }
    }

    func testDraftOmitsEmptyDetail() {
        let without = TriggerDraftBuilder.build(memory: memory(count: 3, detail: ""), imageFiles: files(3),
                                                detailFont: "Lora")
        XCTAssertEqual(texts(without).map(\.block.text), ["10.18 \u{00B7} Arboretum", "What else?"])
        let with = TriggerDraftBuilder.build(memory: memory(count: 3, detail: "Light on the arch"),
                                             imageFiles: files(3),
                                             detailFont: "Lora")
        let ordered = texts(with).sorted { $0.item.position.y < $1.item.position.y }
        XCTAssertEqual(ordered.map(\.block.text), ["10.18 \u{00B7} Arboretum", "Light on the arch", "What else?"])
        XCTAssertEqual(ordered[1].block.fontName, "Lora")
        XCTAssertEqual(ordered[2].block.pointSize, 17)
        XCTAssertEqual(ordered[2].block.fontName, "")
        let photoBottom = images(with).map { $0.item.position.y + $0.item.size.height / 2 }.max() ?? 0
        XCTAssertGreaterThan(ordered[1].item.position.y - ordered[1].item.size.height / 2, photoBottom)
    }

    func testDraftSummariesComeFromFacts() {
        let page = TriggerDraftBuilder.build(memory: memory(count: 3, detail: ""), imageFiles: files(3),
                                             detailFont: "Lora")
        let summaries = Dictionary(uniqueKeysWithValues: images(page).map { ($0.ref.fileName, $0.ref.summary) })
        XCTAssertEqual(summaries, ["file-1.png": "a bench", "file-2.png": "", "file-3.png": "the arch"])
    }

    func testDraftDateIsShootingDay() {
        let page = TriggerDraftBuilder.build(memory: memory(count: 3, detail: ""), imageFiles: files(3),
                                             detailFont: "Lora")
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: page.memoryDate)
        XCTAssertEqual([parts.year, parts.month, parts.day], [2026, 10, 18])
    }

    func testQuestionIsThePagesOnlyPrompt() throws {
        let draft = TriggerDraftBuilder.draft(memory: memory(count: 3, detail: "Light on the arch"),
                                              imageFiles: files(3), detailFont: "Lora")
        XCTAssertEqual(draft.prompts.count, 1)
        let (id, words) = try XCTUnwrap(draft.prompts.first)
        XCTAssertEqual(words, "What else?")
        let item = try XCTUnwrap(draft.page.items.first { $0.id == id })
        guard case .text(let block) = item.content else { return XCTFail("the prompt is a text block") }
        XCTAssertEqual(block.text, "What else?")
    }

    /// Saved untouched, the page keeps the fact and detail lines but not
    /// the question (user decision 2026-11-01).
    @MainActor
    func testUntouchedQuestionIsNotFiled() {
        let draft = TriggerDraftBuilder.draft(memory: memory(count: 3, detail: "Light on the arch"),
                                              imageFiles: files(3), detailFont: "Lora")
        let canvas = CanvasViewModel(memory: draft.page, prompts: draft.prompts)
        let filed = canvas.composedMemory()
        XCTAssertEqual(texts(filed).map(\.block.text).sorted(), ["10.18 \u{00B7} Arboretum", "Light on the arch"])
        XCTAssertEqual(filed.title, "10.18 \u{00B7} Arboretum")
        XCTAssertEqual(filed.body, "Light on the arch")
        XCTAssertEqual(images(filed).count, 3)
        XCTAssertEqual(texts(canvas.memory).count, 3, "the editor still shows the question")
    }

    @MainActor
    func testRewrittenQuestionIsFiled() throws {
        let draft = TriggerDraftBuilder.draft(memory: memory(count: 3, detail: ""), imageFiles: files(3),
                                              detailFont: "Lora")
        let canvas = CanvasViewModel(memory: draft.page, prompts: draft.prompts)
        let id = try XCTUnwrap(draft.prompts.keys.first)
        canvas.setText(itemID: id, to: "What else? The rain, mostly.")
        let filed = canvas.composedMemory()
        XCTAssertEqual(texts(filed).map(\.block.text).sorted(),
                       ["10.18 \u{00B7} Arboretum", "What else? The rain, mostly."])
        XCTAssertEqual(filed.body, "What else? The rain, mostly.")
    }

    func testPhotosWithoutAFileAreLeftOut() {
        var some = files(4)
        some["P2"] = nil
        let page = TriggerDraftBuilder.build(memory: memory(count: 4, detail: ""), imageFiles: some, detailFont: "Lora")
        XCTAssertEqual(images(page).count, 3)
    }
}
