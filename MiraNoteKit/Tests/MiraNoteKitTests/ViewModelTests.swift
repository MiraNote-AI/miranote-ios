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

    func testComposedMemoryDerivesTitleFromMostProminentText() {
        let viewModel = CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
        let composed = viewModel.composedMemory()
        XCTAssertEqual(composed.title, "Lunch by the river", "largest point size wins the title")
        XCTAssertTrue(composed.body.contains("noodle shop"))
        XCTAssertNotNil(composed.savedAt)
        XCTAssertEqual(composed.items.count, viewModel.items.count, "canvas items ride along")
    }

    func testComposedMemoryFallsBackWhenNoText() {
        let viewModel = CanvasViewModel(memory: Memory())
        viewModel.addSound(SoundClip(duration: 3), at: .zero)
        XCTAssertEqual(viewModel.composedMemory().title, "New memory")
    }

    func testAbandonedTextDiscardCompactsHistory() {
        // Tap Text tool, type nothing, dismiss: the husk vanishes and undo
        // does NOT resurrect it (trailing identical snapshots compacted).
        let viewModel = CanvasViewModel(memory: Memory())
        let husk = viewModel.addText("", at: .zero)
        viewModel.startEditingText(husk, recordingUndo: false)
        viewModel.endEditingText()
        viewModel.discardAbandonedText(itemID: husk)
        XCTAssertNil(viewModel.item(husk))
        XCTAssertFalse(viewModel.canUndo, "history holds only states equal to now; all compacted")
    }

    func testAddTypeDoneThenSingleUndoRemovesWholeBlock() {
        // One user action (add-and-type) = one undo step: no intermediate
        // empty-placeholder state.
        let viewModel = CanvasViewModel(memory: Memory())
        let id = viewModel.addText("", at: .zero)
        viewModel.startEditingText(id, recordingUndo: false)
        viewModel.setText(itemID: id, to: "hello river")
        viewModel.endEditingText()
        viewModel.undo()
        XCTAssertNil(viewModel.item(id), "single undo removes the typed block entirely")
    }

    func testRepeatStartEditingBurnsNoSnapshots() {
        let viewModel = CanvasViewModel(memory: Memory())
        let id = viewModel.addText("hi", at: .zero)
        viewModel.startEditingText(id)
        viewModel.startEditingText(id)
        viewModel.startEditingText(id)
        viewModel.endEditingText()
        viewModel.undo()   // editing-session snapshot
        viewModel.undo()   // the add itself
        XCTAssertNil(viewModel.item(id))
        XCTAssertFalse(viewModel.canUndo, "re-entry recorded nothing extra")
    }

    func testMoveClampsIntoReachableCanvas() {
        let viewModel = CanvasViewModel(memory: Memory())
        viewModel.canvasWidth = 360
        let id = viewModel.addText("pin me", at: CGPoint(x: 100, y: 100))
        viewModel.move(itemID: id, to: CGPoint(x: -300, y: -300))
        XCTAssertEqual(viewModel.item(id)?.position, CGPoint(x: 24, y: 24))
        viewModel.move(itemID: id, to: CGPoint(x: 900, y: 50))
        XCTAssertEqual(viewModel.item(id)?.position.x, 336)
    }

    func testImageTreatmentsApplyAndUndoAsOneStep() {
        let viewModel = CanvasViewModel(memory: Memory())
        viewModel.addImages([ImageRef(displayName: "roses", fileName: "r.png")], around: .zero)
        let id = viewModel.items[0].id

        viewModel.setImageFilter(itemID: id, to: "bw")
        viewModel.setImageFrame(itemID: id, to: "polaroid")
        guard case .image(let ref)? = viewModel.item(id)?.content else {
            return XCTFail("expected image content")
        }
        XCTAssertEqual(ref.filterName, "bw")
        XCTAssertEqual(ref.frameName, "polaroid")

        viewModel.undo()
        guard case .image(let afterUndo)? = viewModel.item(id)?.content else {
            return XCTFail("expected image content after undo")
        }
        XCTAssertEqual(afterUndo.frameName, "", "one undo steps back one treatment")
        XCTAssertEqual(afterUndo.filterName, "bw")
    }

    func testReplaceImageWithStickerIsOneUndoableStep() {
        let viewModel = CanvasViewModel(memory: Memory())
        viewModel.addImages([ImageRef(displayName: "roses", fileName: "r.png")], around: .zero)
        let id = viewModel.items[0].id

        let sticker = GeneratedSticker(prompt: "roses", symbolName: "sparkles", fileName: "cut.png")
        viewModel.replaceImageWithSticker(itemID: id, sticker: sticker)
        guard case .sticker(let placed)? = viewModel.item(id)?.content else {
            return XCTFail("expected sticker content")
        }
        XCTAssertEqual(placed.fileName, "cut.png")

        viewModel.undo()
        guard case .image? = viewModel.item(id)?.content else {
            return XCTFail("undo returns the photo")
        }
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
