import XCTest
@testable import MiraNoteKit

/// Image studio double with instant, distinguishable outputs.
struct ScriptedImageStudio: ImageStudioService {
    var generated: [Data] = [Data("img-A".utf8), Data("img-B".utf8)]
    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] { generated }
    func cutout(image: Data, target: String?) async throws -> Data { Data("cut".utf8) }
    func stylize(image: Data, instruction: String) async throws -> Data { Data("styled".utf8) }
    func outline(image: Data) async throws -> Data { Data("outlined".utf8) }
    func describe(image: Data) async throws -> String { "a scripted look" }
}

@MainActor
final class MiraImageTurnTests: XCTestCase {
    private var tempDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mira-image-\(UUID().uuidString)")
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

    func testGenerateAskYieldsTwoChoices() async {
        let editor = CanvasViewModel(memory: Memory())
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.ask("draw a paper crane", editor: editor)
        await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }
        guard case .imageChoices(let images, _, let placement) = coordinator.phase else {
            return XCTFail("expected imageChoices, got \(coordinator.phase)")
        }
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(placement, .picture)
        XCTAssertTrue(editor.items.isEmpty, "nothing lands until a tap")
    }

    func testInstantFilterAppliesWithOneUndo() async {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addImages(
            [ImageRef(displayName: "p", fileName: "p.png")],
            around: CGPoint(x: 150, y: 100)
        ).first!
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.ask("make the photo black and white", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .image(let ref) = editor.item(id)!.content else { return XCTFail("expected an image item") }
        XCTAssertEqual(ref.filterName, "bw")

        editor.undo()
        guard case .image(let restored) = editor.item(id)!.content else { return XCTFail("expected an image item") }
        XCTAssertEqual(restored.filterName, "", "one undo restores the look")
    }

    func testStylizeReplacesPixelsInPlace() async throws {
        let dir = tempDir
        let store = ImageFileStore(directory: dir)
        let fileName = try store.save(Data("orig".utf8), id: UUID())
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addImages(
            [ImageRef(displayName: "p", fileName: fileName)],
            around: CGPoint(x: 150, y: 100)
        ).first!
        let coordinator = makeCoordinator(tempDir: dir)
        coordinator.ask("make the photo feel like autumn", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .image(let ref) = editor.item(id)!.content else { return XCTFail("expected an image item") }
        XCTAssertEqual(store.data(forFileName: ref.fileName), Data("styled".utf8))
    }

    func testMakeStickerReplacesInPlaceAndJoinsFavorites() async throws {
        let dir = tempDir
        let store = ImageFileStore(directory: dir)
        let favorites = StickerFavoritesStore(url: dir.appendingPathComponent("favs.json"))
        let fileName = try store.save(Data("orig".utf8), id: UUID())
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addImages(
            [ImageRef(displayName: "the cat", fileName: fileName)],
            around: CGPoint(x: 150, y: 100)
        ).first!
        let coordinator = makeCoordinator(tempDir: dir)
        coordinator.ask("turn the photo into a sticker", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .sticker(let sticker) = editor.item(id)!.content else {
            return XCTFail("expected a sticker in place")
        }
        XCTAssertEqual(store.data(forFileName: sticker.fileName), Data("outlined".utf8))
        XCTAssertEqual(favorites.all().count, 1, "the cut sticker is reusable")
    }

    func testResizeTextStepsUpAndRecolors() async {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("hello words", at: CGPoint(x: 150, y: 80), pointSize: 17)
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.ask("make it bigger", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .text(let block) = editor.item(id)!.content else { return XCTFail("expected a text item") }
        XCTAssertEqual(block.pointSize, 30, "17 steps up to 30")

        coordinator.dismiss()
        coordinator.ask("make it green", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .text(let recolored) = editor.item(id)!.content else { return XCTFail("expected a text item") }
        XCTAssertEqual(recolored.colorName, "forest")
    }

    func testPlacingAChoiceLandsTheTappedOneAndReceipts() async {
        let dir = tempDir
        let editor = CanvasViewModel(memory: Memory())
        let coordinator = makeCoordinator(tempDir: dir)
        coordinator.ask("draw a paper crane", editor: editor)
        await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }

        coordinator.placeImageChoice(1, editor: editor)
        guard case .receipt(let receipt) = coordinator.phase else {
            return XCTFail("expected a receipt, got \(coordinator.phase)")
        }
        XCTAssertEqual(receipt.changed, "Added a picture.")
        XCTAssertEqual(editor.items.count, 1)
        guard case .image(let ref) = editor.items[0].content else {
            return XCTFail("expected the placed image")
        }
        XCTAssertEqual(
            ImageFileStore(directory: dir).data(forFileName: ref.fileName),
            Data("img-B".utf8),
            "the SECOND candidate landed, not the first"
        )
    }

    func testStickerChoiceJoinsFavorites() async {
        let dir = tempDir
        let favorites = StickerFavoritesStore(url: dir.appendingPathComponent("favs.json"))
        let editor = CanvasViewModel(memory: Memory())
        let coordinator = makeCoordinator(tempDir: dir)
        coordinator.ask("draw a sticker of a coffee cup", editor: editor)
        await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }
        coordinator.placeImageChoice(0, editor: editor)
        XCTAssertEqual(favorites.all().count, 1, "the placed sticker is reusable")
        guard case .sticker = editor.items.first?.content else {
            return XCTFail("expected a sticker element on the canvas")
        }
    }

    func testDiscardKeepsCanvasUntouched() async {
        let editor = CanvasViewModel(memory: Memory())
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.ask("draw a paper crane", editor: editor)
        await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }
        coordinator.discardImageChoices()
        guard case .idle = coordinator.phase else {
            return XCTFail("expected idle after the xmark, got \(coordinator.phase)")
        }
        XCTAssertTrue(editor.items.isEmpty)
        XCTAssertFalse(editor.canUndo, "no snapshot was burned by discarding")
    }

    func testEmptyPhotoBytesFailCalmly() async {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addImages(
            [ImageRef(displayName: "ghost", fileName: "missing.png")],
            around: CGPoint(x: 150, y: 100)
        )
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.ask("make the photo feel like winter", editor: editor)
        await waitUntil { if case .failure = coordinator.phase { return true } else { return false } }
        guard case .failure = coordinator.phase else {
            return XCTFail("expected the calm failure card, got \(coordinator.phase)")
        }
    }
}
