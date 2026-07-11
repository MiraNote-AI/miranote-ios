import XCTest
@testable import MiraNoteKit

/// Appends a stage marker to whatever bytes it receives, so a test can
/// prove every stage ran, on the right input, in the right order.
private struct ChainedImageStudio: ImageStudioService {
    private func stamp(_ image: Data, _ stage: String) -> Data {
        let text = String(bytes: image, encoding: .utf8) ?? "?"
        return Data((text + "+" + stage).utf8)
    }
    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] { [] }
    func cutout(image: Data, target: String?) async throws -> Data { stamp(image, "cut") }
    func stylize(image: Data, instruction: String) async throws -> Data { stamp(image, "styled") }
    func outline(image: Data) async throws -> Data { stamp(image, "outlined") }
    func describe(image: Data) async throws -> String { "a chained look" }
}

@MainActor
final class MiraStickerTurnTests: XCTestCase {
    private var tempDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mira-sticker-\(UUID().uuidString)")
    }

    private func makeCoordinator(
        tempDir: URL, studio: ImageStudioService = ScriptedImageStudio()
    ) -> MiraCanvasCoordinator {
        MiraCanvasCoordinator(
            text: ScriptedText(),
            chat: ScriptedChat(),
            workingDelay: .milliseconds(1),
            timeout: .seconds(5),
            receiptDismiss: .seconds(60),
            imageStudio: studio,
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
            GeneratedSticker(prompt: "the cat", symbolName: "cup", fileName: fileName),
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
        let coordinator = makeCoordinator(tempDir: dir, studio: ChainedImageStudio())
        coordinator.ask("make the sticker blue", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .sticker(let sticker) = editor.item(id)!.content else {
            return XCTFail("expected the item to stay a sticker")
        }
        XCTAssertEqual(store.data(forFileName: sticker.fileName),
                       Data("orig+styled+cut+outlined".utf8),
                       "every stage ran, on the edited bytes, in order")
        XCTAssertEqual(sticker.prompt, "the cat", "the label survives the edit")
        XCTAssertEqual(sticker.symbolName, "cup", "the fallback symbol survives too")
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
