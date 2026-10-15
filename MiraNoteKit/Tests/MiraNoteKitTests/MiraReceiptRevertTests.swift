import XCTest
@testable import MiraNoteKit

/// The result sheet's Revert (screen 07) only ever takes back Mira's own
/// change: never words typed after it, never a change made elsewhere.
@MainActor
final class MiraReceiptRevertTests: XCTestCase {
    private func makeEditor() -> CanvasViewModel {
        CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
    }

    private func makeCoordinator() -> MiraCanvasCoordinator {
        MiraCanvasCoordinator(
            text: ScriptedText(), chat: ScriptedChat(), workingDelay: .milliseconds(1), timeout: .seconds(5)
        )
    }

    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // Typing goes through setText, which records no step: Revert must still
    // see it, or it undoes to before the typed words (there is no Redo).
    func testRevertKeepsWordsTypedAfterTheResult() async throws {
        let editor = makeEditor()
        let coordinator = makeCoordinator()
        coordinator.ask("polish the text", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        XCTAssertTrue(coordinator.receiptCanRevert)

        let title = try XCTUnwrap(editor.items.first { if case .text = $0.content { return true }; return false })
        editor.setText(itemID: title.id, to: "first words, then a paragraph")
        coordinator.canvasDidChange(editor)
        XCTAssertFalse(coordinator.receiptCanRevert, "Revert would take the typed words too")

        coordinator.revert(editor: editor)
        guard case .text(let block) = editor.item(title.id)?.content else { return XCTFail("block gone") }
        XCTAssertEqual(block.text, "first words, then a paragraph")
        XCTAssertEqual(coordinator.phase, .idle)
    }

    // The view re-measures blocks after Mira's change (no step): that is
    // not an edit, so Revert stays.
    func testRemeasuringAfterTheResultKeepsRevert() async throws {
        let editor = makeEditor()
        let coordinator = makeCoordinator()
        coordinator.ask("polish the text", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        let block = try XCTUnwrap(editor.items.first { if case .text = $0.content { return true }; return false })
        editor.autosizeTextHeight(itemID: block.id, to: block.size.height + 30)
        XCTAssertTrue(coordinator.receiptCanRevert)
    }

    // A change made where CanvasScene is not mounted (a Sticker preset)
    // never reaches canvasDidChange: Revert must not be offered for it.
    func testRevertIsNotOfferedOnceSomethingElseChanged() async {
        let editor = makeEditor()
        let coordinator = makeCoordinator()
        coordinator.ask("polish the text", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }

        editor.addImages([ImageRef(displayName: "martini", fileName: "martini.png")], around: CGPoint(x: 100, y: 500))
        XCTAssertFalse(coordinator.receiptCanRevert)
    }
}
