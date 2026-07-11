import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraStickerTurnTests: XCTestCase {
    private var tempDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mira-sticker-\(UUID().uuidString)")
    }

    private func makeCoordinator(tempDir: URL) -> MiraCanvasCoordinator {
        MiraCanvasCoordinator(
            text: ScriptedText(),
            chat: ScriptedChat(),
            workingDelay: .milliseconds(1),
            timeout: .seconds(5),
            receiptDismiss: .seconds(60),
            imageStudio: ScriptedImageStudio(),
            imageTimeout: .seconds(5),
            imageStore: ImageFileStore(directory: tempDir),
            stickerFavorites: StickerFavoritesStore(
                url: tempDir.appendingPathComponent("favs.json"))
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func placeSticker(in editor: CanvasViewModel, store: ImageFileStore) throws -> CanvasItem.ID {
        let fileName = try store.save(Data("orig".utf8), id: UUID())
        editor.addSticker(
            GeneratedSticker(prompt: "the cat", symbolName: "sparkles", fileName: fileName),
            at: CGPoint(x: 150, y: 100)
        )
        return editor.items.last!.id
    }

    func testEditReplacesPixelsInPlaceThroughTheFullCut() async throws {
        let dir = tempDir
        let store = ImageFileStore(directory: dir)
        let favorites = StickerFavoritesStore(url: dir.appendingPathComponent("favs.json"))
        let editor = CanvasViewModel(memory: Memory())
        let id = try placeSticker(in: editor, store: store)
        let coordinator = makeCoordinator(tempDir: dir)
        coordinator.ask("make the sticker blue", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .sticker(let sticker) = editor.item(id)!.content else {
            return XCTFail("expected the item to stay a sticker")
        }
        XCTAssertEqual(store.data(forFileName: sticker.fileName), Data("outlined".utf8),
                       "stylize -> cutout -> outline ran to the end")
        XCTAssertEqual(sticker.prompt, "the cat", "the label survives the edit")
        XCTAssertEqual(favorites.all().count, 1, "the edited sticker is reusable")
    }

    func testOneUndoRestoresTheOldSticker() async throws {
        let dir = tempDir
        let store = ImageFileStore(directory: dir)
        let editor = CanvasViewModel(memory: Memory())
        let id = try placeSticker(in: editor, store: store)
        let coordinator = makeCoordinator(tempDir: dir)
        coordinator.ask("make the sticker blue", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }

        editor.undo()
        guard case .sticker(let restored) = editor.item(id)!.content else {
            return XCTFail("expected a sticker after undo")
        }
        XCTAssertEqual(store.data(forFileName: restored.fileName), Data("orig".utf8),
                       "one undo brings the old pixels back")
    }

    func testMissingPixelsFailCalmly() async {
        let editor = CanvasViewModel(memory: Memory())
        editor.addSticker(
            GeneratedSticker(prompt: "ghost", symbolName: "sparkles", fileName: "missing.png"),
            at: CGPoint(x: 150, y: 100)
        )
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.ask("make the sticker blue", editor: editor)
        await waitUntil { if case .failure = coordinator.phase { return true } else { return false } }
        guard case .failure = coordinator.phase else {
            return XCTFail("expected the calm clarify card, got \(coordinator.phase)")
        }
        XCTAssertEqual(editor.items.count, 1, "canvas untouched")
    }
}
