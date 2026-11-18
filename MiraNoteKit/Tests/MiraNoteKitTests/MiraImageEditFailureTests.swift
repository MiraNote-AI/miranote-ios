import XCTest
@testable import MiraNoteKit

/// A studio whose edits fail the way /stylize does (miranote-api #103).
private struct FailingEditStudio: ImageStudioService {
    let error: Error
    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] { [] }
    func cutout(image: Data, target: String?) async throws -> Data { image }
    func stylize(image: Data, instruction: String) async throws -> Data { throw error }
    func outline(image: Data) async throws -> Data { image }
    func describe(image: Data) async throws -> String { "a look" }
}

/// When an edit Mira was asked for fails with a reason, her card says that
/// reason in the app's words, as the Photo and Sticker editors do -- not
/// "That one did not go through".
@MainActor
final class MiraImageEditFailureTests: XCTestCase {
    private func coordinator(_ error: Error, chat: ScriptedChat = ScriptedChat(),
                             store: ImageFileStore, dir: URL) -> MiraCanvasCoordinator {
        MiraCanvasCoordinator(
            text: ScriptedText(), chat: chat,
            workingDelay: .milliseconds(1), timeout: .seconds(5),
            imageStudio: FailingEditStudio(error: error), imageTimeout: .seconds(5),
            imageStore: store,
            stickerFavorites: StickerFavoritesStore(url: dir.appendingPathComponent("favs.json"))
        )
    }

    private func failure(of mira: MiraCanvasCoordinator) async -> MiraFailure? {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if case .failure(let failure) = mira.phase { return failure }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mira-edit-failure-\(UUID().uuidString)")
    }

    func testARefusedPhotoEditSaysWhy() async throws {
        let dir = tempDir()
        let store = ImageFileStore(directory: dir)
        let name = try store.save(MockImageStudioService.tinyPNG, id: UUID())
        let board = CanvasViewModel(memory: Memory(items: [CanvasItem(
            content: .image(ImageRef(displayName: "d", fileName: name, summary: "a grey bowl")),
            position: CGPoint(x: 180, y: 300), size: CGSize(width: 280, height: 200)
        )]))
        var chat = ScriptedChat()
        chat.reply = "Warming it up."
        chat.photoRestyle = PhotoRestyleRequest(handle: "p1", instruction: "warmer")
        let refused = ImageEditError(status: 422, reason: "edit_refused", message: "server words")
        let mira = coordinator(refused, chat: chat, store: store, dir: dir)

        mira.ask("warm the photo", editor: board)
        let failure = await failure(of: mira)

        XCTAssertEqual(failure?.message, "Mira won't make that edit. Try describing it differently.")
    }

    func testABusyStickerEditSaysWhy() async throws {
        let dir = tempDir()
        let store = ImageFileStore(directory: dir)
        let board = CanvasViewModel(memory: Memory())
        board.addSticker(
            GeneratedSticker(prompt: "the cat", symbolName: "cup",
                             fileName: try store.save(MockImageStudioService.tinyPNG, id: UUID())),
            at: CGPoint(x: 150, y: 100)
        )
        let busy = ImageEditError(status: 503, reason: "busy", message: "server words")
        let mira = coordinator(busy, store: store, dir: dir)

        mira.ask("make the sticker blue", editor: board)
        let failure = await failure(of: mira)

        XCTAssertEqual(failure?.message, "Mira is busy right now. Wait a moment and try again.")
        XCTAssertEqual(failure?.kind, .retry)
    }

    /// Any other failure keeps the card's own words.
    func testAnotherFailureKeepsTheGeneralWords() async throws {
        let dir = tempDir()
        let store = ImageFileStore(directory: dir)
        let board = CanvasViewModel(memory: Memory())
        board.addSticker(
            GeneratedSticker(prompt: "the cat", symbolName: "cup",
                             fileName: try store.save(MockImageStudioService.tinyPNG, id: UUID())),
            at: CGPoint(x: 150, y: 100)
        )
        let mira = coordinator(BackendError.server(status: 500, detail: nil), store: store, dir: dir)

        mira.ask("make the sticker blue", editor: board)
        let failure = await failure(of: mira)

        XCTAssertEqual(failure?.message, "That one did not go through. Try again, or say it differently?")
    }
}
