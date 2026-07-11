import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraBackgroundTurnTests: XCTestCase {
    private var tempDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mira-bg-\(UUID().uuidString)")
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

    func testBackgroundAskYieldsChoicesAndPlacingSetsIt() async {
        let dir = tempDir
        let editor = CanvasViewModel(memory: Memory())
        let coordinator = makeCoordinator(tempDir: dir)
        coordinator.ask("give this page a sunset background", editor: editor)
        await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }
        guard case .imageChoices(let images, _, let placement) = coordinator.phase else {
            return XCTFail("expected imageChoices, got \(coordinator.phase)")
        }
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(placement, .background)
        XCTAssertTrue(editor.memory.backgroundFileName.isEmpty, "nothing lands until a tap")

        coordinator.placeImageChoice(1, editor: editor)
        guard case .receipt(let receipt) = coordinator.phase else {
            return XCTFail("expected a receipt, got \(coordinator.phase)")
        }
        XCTAssertEqual(receipt.changed, "Set the page background.")
        XCTAssertEqual(
            ImageFileStore(directory: dir).data(forFileName: editor.memory.backgroundFileName),
            Data("img-B".utf8),
            "the SECOND candidate became the background")
        XCTAssertTrue(editor.items.isEmpty, "no canvas element was added")

        editor.undo()
        XCTAssertEqual(editor.memory.backgroundFileName, "", "one undo removes it")
    }

    func testClearAskRemovesTheBackgroundWithOneUndo() async {
        let editor = CanvasViewModel(memory: Memory(backgroundFileName: "bg.png"))
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.ask("remove the background", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .receipt(let receipt) = coordinator.phase else {
            return XCTFail("expected a receipt, got \(coordinator.phase)")
        }
        XCTAssertEqual(receipt.changed, "Cleared the background.")
        XCTAssertEqual(editor.memory.backgroundFileName, "")
        editor.undo()
        XCTAssertEqual(editor.memory.backgroundFileName, "bg.png")
    }
}
