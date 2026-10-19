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

    // The background chip's ask quotes the page's own words, which can
    // carry router keywords ("photo"). The chip says what it means, so the
    // turn is a background turn whatever the words -- on Retry too.
    func testBackgroundChipStaysABackgroundTurnWhateverThePageSays() async {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText("photo dump from the trip", at: CGPoint(x: 100, y: 100), pointSize: 30)
        _ = editor.addImages([ImageRef(displayName: "trip", fileName: "t.png")], around: CGPoint(x: 100, y: 300))
        let coordinator = makeCoordinator(tempDir: tempDir)

        coordinator.askSuggestion(MiraCanvasCoordinator.changeBackgroundChip, editor: editor)
        await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }
        guard case .imageChoices(_, _, let placement) = coordinator.phase else {
            return XCTFail("expected background choices, got \(coordinator.phase)")
        }
        XCTAssertEqual(placement, .background)

        coordinator.retry(editor: editor)
        await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }
        guard case .imageChoices(_, _, let again) = coordinator.phase else {
            return XCTFail("Retry must rerun the background turn, got \(coordinator.phase)")
        }
        XCTAssertEqual(again, .background)
    }

    // The Background tool's "Apply to this page": whatever the words say,
    // they describe a backdrop -- photo words included -- and Apply puts
    // it on the page (owner, TestFlight 1.0(5)).
    func testApplyToThisPagePaintsABackdropFromAnyWords() async {
        let editor = CanvasViewModel(memory: Memory())
        let photo = editor.addImages([ImageRef(displayName: "trip", fileName: "t.png")],
                                     around: CGPoint(x: 100, y: 300))[0]
        let coordinator = makeCoordinator(tempDir: tempDir)

        coordinator.askBackground("  a garden behind my photo  ", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .receipt(let receipt) = coordinator.phase else {
            return XCTFail("expected the backdrop on the page, got \(coordinator.phase)")
        }
        XCTAssertEqual(receipt.changed, "Set the page background.")
        XCTAssertFalse(editor.memory.backgroundFileName.isEmpty)
        XCTAssertEqual(editor.memory.backgroundSummary, "a garden behind my photo")
        guard case .image(let ref) = editor.item(photo)?.content else { return XCTFail("the photo is gone") }
        XCTAssertEqual(ref.fileName, "t.png", "the photo words did not become a photo edit")
    }

    func testApplyToThisPageWithNoWordsDoesNothing() {
        let editor = CanvasViewModel(memory: Memory())
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.askBackground("   ", editor: editor)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertFalse(coordinator.isWorking)
    }

    // Screen 06's primary chip paints for the page, like the old idle chip.
    func testChangeBackgroundQuickActionIsABackgroundTurn() async {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText("photo dump from the trip", at: CGPoint(x: 100, y: 100), pointSize: 30)
        let coordinator = makeCoordinator(tempDir: tempDir)
        XCTAssertEqual(MiraCanvasCoordinator.quickActions.first, "Change background")

        coordinator.askQuickAction("Change background", editor: editor)
        await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }
        guard case .imageChoices(_, _, let placement) = coordinator.phase else {
            return XCTFail("expected background choices, got \(coordinator.phase)")
        }
        XCTAssertEqual(placement, .background)
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
