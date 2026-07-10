import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraPageIntentTests: XCTestCase {
    private func makeCoordinator() -> MiraCanvasCoordinator {
        MiraCanvasCoordinator(
            text: ScriptedText(),
            chat: ScriptedChat(),
            workingDelay: .milliseconds(1),
            timeout: .seconds(5),
            receiptDismiss: .seconds(60)
        )
    }

    private func makeEditor() -> CanvasViewModel {
        CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testOrganizeAndTitleIntents() async {
        let editor = makeEditor()
        let coordinator = makeCoordinator()

        coordinator.ask("tidy the layout", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .receipt(let organized) = coordinator.phase else { return XCTFail("expected an organize receipt") }
        XCTAssertEqual(organized.changed, "Tidied the layout.")

        coordinator.dismiss()
        let countBefore = editor.items.count
        coordinator.ask("add a soft title", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        XCTAssertEqual(editor.items.count, countBefore + 1, "a title block landed")
        let texts = editor.items.compactMap { item -> String? in
            if case .text(let block) = item.content { return block.text }
            return nil
        }
        XCTAssertTrue(
            texts.contains("Scripted reply"),
            "the title comes from the AI reply (cleaned), not a placeholder"
        )
    }

    func testCaptionAsksTheAIAndLandsUnderTheContent() async {
        let editor = makeEditor()
        let coordinator = makeCoordinator()
        let bottomBefore = editor.contentBottom

        coordinator.ask("write something about this photo, a caption", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }

        guard case .receipt(let receipt) = coordinator.phase else { return XCTFail("expected receipt") }
        XCTAssertEqual(receipt.changed, "Added a few words.")
        let texts = editor.items.compactMap { item -> String? in
            if case .text(let block) = item.content { return block.text }
            return nil
        }
        XCTAssertTrue(texts.contains("Scripted reply."), "the caption is the AI reply")
        let added = editor.items.first { item in
            if case .text(let block) = item.content { return block.text == "Scripted reply." }
            return false
        }
        XCTAssertGreaterThan(
            (added?.position.y ?? 0), bottomBefore,
            "captions read under the page content"
        )
    }

    // A two-line title is taller than the old fixed 60pt box: it must
    // size to its words and push the page down, never overlap it.
    func testLongTitleSizesItselfAndPushesContentDown() async {
        let editor = CanvasViewModel(memory: Memory())
        let bodyID = editor.addText(
            "croissants at the corner bakery",
            at: CGPoint(x: 150, y: 60),
            pointSize: 15,
            size: CGSize(width: 220, height: 40)
        )
        let coordinator = MiraCanvasCoordinator(
            text: ScriptedText(),
            chat: ScriptedChat(reply: "Warm flaky croissants at dawn"),
            workingDelay: .milliseconds(1),
            timeout: .seconds(5),
            receiptDismiss: .seconds(60)
        )

        coordinator.ask("add a soft title", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }

        guard let title = editor.items.first(where: { item in
            if case .text(let block) = item.content { return block.pointSize == 30 }
            return false
        }), let body = editor.item(bodyID) else {
            return XCTFail("expected a title block and the original body")
        }

        let titleBottom = title.position.y + title.size.height / 2
        let bodyTop = body.position.y - body.size.height / 2
        XCTAssertGreaterThan(title.size.height, 60, "two lines need more than the one-line box")
        XCTAssertGreaterThanOrEqual(title.position.y - title.size.height / 2, 24, "title stays on the paper")
        XCTAssertLessThanOrEqual(titleBottom, bodyTop - 8, "the title never covers the words below it")

        editor.undo()
        XCTAssertEqual(editor.item(bodyID)?.position.y, 60, "one undo restores the pushed-down page")
        XCTAssertEqual(editor.items.count, 1, "and removes the title")
    }
}
