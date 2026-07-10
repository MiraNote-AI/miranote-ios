import XCTest
@testable import MiraNoteKit

final class CanvasItemCodableTests: XCTestCase {
    func testMemoryItemsSurviveEncodeDecode() throws {
        let items: [CanvasItem] = [
            CanvasItem(
                content: .text(TextBlock(text: "title", pointSize: 30, colorName: "ink")),
                position: CGPoint(x: 118, y: 46),
                size: CGSize(width: 200, height: 76),
                rotation: -4,
                zIndex: 7
            ),
            CanvasItem(content: .image(ImageRef(displayName: "roses")), position: CGPoint(x: 60, y: 200)),
            CanvasItem(
                content: .sticker(GeneratedSticker(prompt: "cup", symbolName: "cup.and.saucer.fill")),
                position: .zero
            ),
            CanvasItem(
                content: .sound(SoundClip(duration: 12.5, note: "noodle shop", fileName: "a.m4a")),
                position: .zero
            )
        ]
        let memory = Memory(title: "Lunch by the river", items: items)
        let data = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(Memory.self, from: data)
        XCTAssertEqual(decoded.items, items)
        XCTAssertEqual(decoded, memory)
    }

    func testLegacyMemoryWithoutItemsDecodesEmpty() throws {
        let legacy = Data("""
        {"id":"\(UUID().uuidString)","title":"old","createdAt":700000000}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(Memory.self, from: legacy)
        XCTAssertEqual(decoded.items, [])
    }
}

final class SoundFileStoreTests: XCTestCase {
    func testSaveRoundTripAndDelete() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sound-store-test-\(UUID().uuidString)")
        let store = SoundFileStore(directory: dir)
        let id = UUID()

        let fileName = try store.save(Data("audio-bytes".utf8), id: id)
        XCTAssertTrue(store.exists(fileName: fileName))
        XCTAssertEqual(try Data(contentsOf: store.url(forFileName: fileName)), Data("audio-bytes".utf8))

        store.delete(fileName: fileName)
        XCTAssertFalse(store.exists(fileName: fileName))
        try? FileManager.default.removeItem(at: dir)
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
