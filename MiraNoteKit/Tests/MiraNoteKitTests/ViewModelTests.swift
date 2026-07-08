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

    func testAddCollectionAppendsAndIgnoresBlank() {
        let viewModel = HomeViewModel(collections: [])
        viewModel.addCollection(title: "New notebook")
        viewModel.addCollection(title: "   ")
        XCTAssertEqual(viewModel.collections.count, 1)
        XCTAssertEqual(viewModel.collections[0].title, "New notebook")
    }

    func testAddNoteAppendsToNamedCollection() {
        let seed = [MemoryCollection(title: "Log")]
        let viewModel = HomeViewModel(collections: seed)
        viewModel.addNote(titled: "First note", to: seed[0].id)
        XCTAssertEqual(viewModel.collection(seed[0].id)?.memories.count, 1)
        XCTAssertEqual(viewModel.collection(seed[0].id)?.memories.first?.title, "First note")
    }

    func testChangesPersistThroughAFileStore() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = HomeViewModel(store: FileCollectionStore(url: url))
        let before = first.collections.count
        first.addCollection(title: "Persisted")

        let second = HomeViewModel(store: FileCollectionStore(url: url))
        XCTAssertEqual(second.collections.count, before + 1)
        XCTAssertTrue(second.collections.contains { $0.title == "Persisted" })
    }

    func testUpdateNoteEditsTitleAndBody() {
        let seed = [MemoryCollection(title: "Log", memories: [Memory(title: "Draft")])]
        let viewModel = HomeViewModel(collections: seed)
        let noteID = seed[0].memories[0].id

        viewModel.updateNote(noteID, in: seed[0].id, title: "Kyoto trip", body: "Rainy morning.")

        let note = viewModel.note(noteID, in: seed[0].id)
        XCTAssertEqual(note?.title, "Kyoto trip")
        XCTAssertEqual(note?.body, "Rainy morning.")
        XCTAssertNotNil(note?.savedAt, "editing a note stamps savedAt")
    }

    func testNoteEditsPersistThroughAFileStore() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("note-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = HomeViewModel(store: FileCollectionStore(url: url))
        let collection = first.collections[0]
        let noteID = collection.memories[0].id
        first.updateNote(noteID, in: collection.id, title: "Kept", body: "Persisted body.")

        let second = HomeViewModel(store: FileCollectionStore(url: url))
        XCTAssertEqual(second.note(noteID, in: collection.id)?.body, "Persisted body.")
        XCTAssertEqual(second.note(noteID, in: collection.id)?.title, "Kept")
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

    // MARK: v2.1 editor core

    func testNewElementsStackAboveExisting() {
        let viewModel = CanvasViewModel(memory: Memory())
        let textID = viewModel.addText("first", at: .zero)
        let soundID = viewModel.addSound(SoundClip(duration: 12), at: .zero)
        let textZ = viewModel.item(textID)?.zIndex ?? .max
        let soundZ = viewModel.item(soundID)?.zIndex ?? .min
        XCTAssertGreaterThan(soundZ, textZ)
        XCTAssertEqual(viewModel.orderedItems.last?.id, soundID)
    }

    func testDuplicateOffsetsCopyAndSelectsIt() {
        let viewModel = CanvasViewModel(memory: Memory())
        let original = viewModel.addText("hello", at: CGPoint(x: 100, y: 100))
        let copy = viewModel.duplicate(itemID: original)
        XCTAssertNotNil(copy)
        XCTAssertEqual(viewModel.items.count, 2)
        XCTAssertEqual(viewModel.item(copy!)?.position, CGPoint(x: 116, y: 116))
        XCTAssertEqual(viewModel.selectedItemID, copy)
        XCTAssertGreaterThan(viewModel.item(copy!)!.zIndex, viewModel.item(original)!.zIndex)
    }

    func testDeleteRemovesAndUndoRestores() {
        let viewModel = CanvasViewModel(memory: Memory())
        let id = viewModel.addText("keep me", at: .zero)
        viewModel.select(id)
        viewModel.delete(itemID: id)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(viewModel.selectedItemID)

        viewModel.undo()
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.item(id)?.id, id)
    }

    func testUndoStepsBackOneGestureNotOneTick() {
        let viewModel = CanvasViewModel(memory: Memory())
        let id = viewModel.addText("dragged", at: CGPoint(x: 10, y: 10))
        viewModel.beginChange()
        viewModel.move(itemID: id, to: CGPoint(x: 50, y: 50))
        viewModel.move(itemID: id, to: CGPoint(x: 90, y: 90))
        viewModel.move(itemID: id, to: CGPoint(x: 130, y: 130))
        viewModel.undo()
        XCTAssertEqual(viewModel.item(id)?.position, CGPoint(x: 10, y: 10))
    }

    func testResizeClampsToMinimum() {
        let viewModel = CanvasViewModel(memory: Memory())
        let id = viewModel.addText("tiny", at: .zero)
        viewModel.resize(itemID: id, to: CGSize(width: 2, height: 2))
        XCTAssertEqual(viewModel.item(id)?.size, CGSize(width: 44, height: 36))
    }

    func testLayerOrderOperations() {
        let viewModel = CanvasViewModel(memory: Memory())
        let first = viewModel.addText("a", at: .zero)
        let second = viewModel.addText("b", at: .zero)
        viewModel.sendToBack(itemID: second)
        XCTAssertEqual(viewModel.orderedItems.first?.id, second)
        viewModel.bringToFront(itemID: second)
        XCTAssertEqual(viewModel.orderedItems.last?.id, second)
        XCTAssertEqual(viewModel.orderedItems.first?.id, first)
    }

    func testSoundNoteEditAndTextEdits() {
        let viewModel = CanvasViewModel(memory: Memory())
        let soundID = viewModel.addSound(SoundClip(duration: 8, note: ""), at: .zero)
        viewModel.setSoundNote(itemID: soundID, to: "noodle shop")
        guard case .sound(let clip)? = viewModel.item(soundID)?.content else {
            return XCTFail("expected sound content")
        }
        XCTAssertEqual(clip.note, "noodle shop")

        let textID = viewModel.addText("draft", at: .zero)
        viewModel.startEditingText(textID)
        XCTAssertEqual(viewModel.editingTextItemID, textID)
        viewModel.setText(itemID: textID, to: "draft, polished by hand")
        viewModel.setTextPointSize(itemID: textID, to: 28)
        viewModel.endEditingText()
        guard case .text(let block)? = viewModel.item(textID)?.content else {
            return XCTFail("expected text content")
        }
        XCTAssertEqual(block.text, "draft, polished by hand")
        XCTAssertEqual(block.pointSize, 28)
    }

    func testContentBottomTracksLowestElement() {
        let viewModel = CanvasViewModel(memory: Memory())
        XCTAssertEqual(viewModel.contentBottom, 0)
        viewModel.addText("low", at: CGPoint(x: 0, y: 900), size: CGSize(width: 100, height: 100))
        XCTAssertEqual(viewModel.contentBottom, 950)
    }

    func testSelectingAnotherItemEndsTextEditing() {
        let viewModel = CanvasViewModel(memory: Memory())
        let textID = viewModel.addText("editing", at: .zero)
        let otherID = viewModel.addText("other", at: .zero)
        viewModel.startEditingText(textID)
        viewModel.select(otherID)
        XCTAssertNil(viewModel.editingTextItemID)
        XCTAssertEqual(viewModel.selectedItemID, otherID)
    }
}

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
