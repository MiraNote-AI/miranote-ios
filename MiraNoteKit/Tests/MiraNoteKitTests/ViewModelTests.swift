import XCTest
@testable import MiraNoteKit

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testEmptyStateHintShownWhenNoCollections() {
        let viewModel = HomeViewModel()
        XCTAssertTrue(viewModel.showsEmptyStateHint, "D3: empty Home must show the guidance hint")
    }

    func testEmptyStateHintHiddenWithCollections() {
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Trips")])
        XCTAssertFalse(viewModel.showsEmptyStateHint)
    }

    func testStartMemoryReturnsBlankCanvas() {
        let memory = HomeViewModel().startMemory()
        XCTAssertTrue(memory.items.isEmpty)
        XCTAssertNil(memory.savedAt)
    }

    func testFileMemoryCreatesCollectionOnFirstUse() {
        let viewModel = HomeViewModel()
        viewModel.file(Memory(), underCollectionTitled: "Trips")
        viewModel.file(Memory(), underCollectionTitled: "Trips")
        XCTAssertEqual(viewModel.collections.count, 1)
        XCTAssertEqual(viewModel.collections[0].memories.count, 2)
    }

    func testRefilingSameMemoryReplacesInsteadOfDuplicating() {
        let viewModel = HomeViewModel()
        var memory = Memory(title: "first save")
        viewModel.file(memory, underCollectionTitled: "Trips")
        memory.title = "second save"
        viewModel.file(memory, underCollectionTitled: "Trips")
        XCTAssertEqual(viewModel.collections[0].memories.count, 1, "repeated Save must not duplicate")
        XCTAssertEqual(viewModel.collections[0].memories[0].title, "second save")
    }
}

@MainActor
final class CanvasViewModelTests: XCTestCase {
    func testAddTextImageStickerLandOnCanvas() {
        let viewModel = CanvasViewModel(memory: Memory())
        viewModel.addText("hello", at: CGPoint(x: 10, y: 10))
        viewModel.addImages([ImageRef(displayName: "one"), ImageRef(displayName: "two")], around: .zero)
        viewModel.addSticker(GeneratedSticker(prompt: "cat", symbolName: "sparkles"), at: .zero)
        XCTAssertEqual(viewModel.items.count, 4)
    }

    func testSaveStampsSavedAt() {
        let viewModel = CanvasViewModel(memory: Memory())
        XCTAssertNil(viewModel.memory.savedAt)
        viewModel.save()
        XCTAssertNotNil(viewModel.memory.savedAt)
    }

    func testQuickOrganizeSnapsToGridPreservingOrder() {
        let viewModel = CanvasViewModel(memory: Memory())
        for index in 0..<5 {
            viewModel.addText("item \(index)", at: CGPoint(x: 999, y: 999))
        }
        viewModel.quickOrganize(canvasWidth: 240, spacing: 120)
        let positions = viewModel.items.map(\.position)
        XCTAssertEqual(positions[0], CGPoint(x: 60, y: 60))
        XCTAssertEqual(positions[1], CGPoint(x: 180, y: 60))
        XCTAssertEqual(positions[2], CGPoint(x: 60, y: 180))
        XCTAssertEqual(Set(positions.map { "\($0)" }).count, 5, "no two items share a slot")
    }
}

@MainActor
final class TextInputViewModelTests: XCTestCase {
    func testApplyPolishTransformsText() async {
        let viewModel = TextInputViewModel(text: "draft words")
        await viewModel.apply(.polish)
        XCTAssertTrue(viewModel.text.contains("draft words"))
        XCTAssertNotEqual(viewModel.text, "draft words", "polish must change the text via the service")
        XCTAssertFalse(viewModel.isProcessing)
    }

    func testApplyIgnoredForEmptyText() async {
        let viewModel = TextInputViewModel(text: "   ")
        await viewModel.apply(.clean)
        XCTAssertEqual(viewModel.text, "   ", "blank input must not be sent to the service")
    }

    func testDictateAppendsTranscript() async {
        let viewModel = TextInputViewModel(text: "existing", recorder: MockAudioRecorder())
        await viewModel.toggleDictation()
        XCTAssertTrue(viewModel.isRecording, "first tap starts recording")
        await viewModel.toggleDictation()
        XCTAssertFalse(viewModel.isRecording, "second tap stops recording")
        XCTAssertTrue(viewModel.text.hasPrefix("existing\n"))
        XCTAssertGreaterThan(viewModel.text.count, "existing".count)
    }
}

@MainActor
final class AIStickerViewModelTests: XCTestCase {
    func testGenerateRequiresPrompt() {
        XCTAssertFalse(AIStickerViewModel().canGenerate)
        XCTAssertTrue(AIStickerViewModel(prompt: "a happy cat").canGenerate)
    }

    func testGenerateProducesSticker() async {
        let viewModel = AIStickerViewModel(prompt: "a happy cat")
        await viewModel.generate()
        XCTAssertEqual(viewModel.generated?.prompt, "a happy cat")
        XCTAssertFalse(viewModel.isGenerating)
    }

    func testDictateAppendsToPrompt() async {
        let viewModel = AIStickerViewModel(prompt: "a cat", recorder: MockAudioRecorder())
        await viewModel.toggleDictation()
        await viewModel.toggleDictation()
        XCTAssertTrue(viewModel.prompt.hasPrefix("a cat "), "A3: dictation appends to the prompt")
        XCTAssertGreaterThan(viewModel.prompt.count, "a cat ".count)
    }
}

@MainActor
final class StyleTransferViewModelTests: XCTestCase {
    private func makeImages(_ count: Int) -> [ImageRef] {
        (0..<count).map { ImageRef(displayName: "img\($0)") }
    }

    func testImageCapEnforced() {
        let viewModel = StyleTransferViewModel()
        viewModel.addImages(makeImages(10))
        XCTAssertEqual(
            viewModel.images.count,
            MiraNoteConfig.maxImagesPerAdd,
            "D1: adding ten images must clamp to the cap"
        )
        XCTAssertFalse(viewModel.canAddMore)
    }

    func testCapIsThree() {
        XCTAssertEqual(MiraNoteConfig.maxImagesPerAdd, 3, "D1 decision pins the cap at 3")
    }

    func testRemoveFreesSlot() {
        let viewModel = StyleTransferViewModel()
        viewModel.addImages(makeImages(3))
        viewModel.removeImage(id: viewModel.images[0].id)
        XCTAssertEqual(viewModel.remainingSlots, 1)
        XCTAssertTrue(viewModel.canAddMore)
    }

    func testChangingInputsInvalidatesResults() async {
        let viewModel = StyleTransferViewModel()
        viewModel.addImages(makeImages(1))
        viewModel.selectedStyle = .cartoon
        await viewModel.generate()
        XCTAssertNotNil(viewModel.results)
        viewModel.selectedStyle = .vintage
        XCTAssertNil(viewModel.results, "stale results must not survive a style change")
        await viewModel.generate()
        XCTAssertNotNil(viewModel.results)
        viewModel.addImages(makeImages(1))
        XCTAssertNil(viewModel.results, "stale results must not survive an input change")
    }

    func testGenerateNeedsImagesAndStyle() async {
        let viewModel = StyleTransferViewModel()
        XCTAssertFalse(viewModel.canGenerate)
        viewModel.addImages(makeImages(2))
        XCTAssertFalse(viewModel.canGenerate, "style not chosen yet")
        viewModel.selectedStyle = .handDrawn
        XCTAssertTrue(viewModel.canGenerate)
        await viewModel.generate()
        XCTAssertEqual(viewModel.results?.count, 2)
        XCTAssertTrue(viewModel.results?.allSatisfy { $0.displayName.contains("Hand-drawn") } ?? false)
    }
}
