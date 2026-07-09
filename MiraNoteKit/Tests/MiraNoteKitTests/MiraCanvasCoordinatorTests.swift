import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraCanvasCoordinatorTests: XCTestCase {
    private func makeEditor() -> CanvasViewModel {
        CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
    }

    private func makeCoordinator(
        text: TextTransformService = ScriptedText(),
        chat: ChatService = ScriptedChat(),
        workingDelay: Duration = .milliseconds(1),
        timeout: Duration = .seconds(5),
        receiptDismiss: Duration = .seconds(60)
    ) -> MiraCanvasCoordinator {
        MiraCanvasCoordinator(
            text: text,
            chat: chat,
            workingDelay: workingDelay,
            timeout: timeout,
            receiptDismiss: receiptDismiss
        )
    }

    /// Spin until the condition holds or the deadline passes.
    private func waitUntil(
        _ timeout: Duration = .seconds(3),
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testPolishAppliesAtomicallyWithReceiptAndRevert() async {
        let editor = makeEditor()
        let coordinator = makeCoordinator()
        let bodyBefore = "Sunny afternoon, tiny noodle shop by the bridge"

        coordinator.ask("polish the text", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }

        guard case .receipt(let receipt) = coordinator.phase else {
            return XCTFail("expected a receipt, got \(coordinator.phase)")
        }
        XCTAssertEqual(receipt.changed, "Polished the text.")
        XCTAssertTrue(receipt.kept.contains("stayed put"), "receipt names what was kept")
        let bodyTexts = editor.items.compactMap { item -> String? in
            if case .text(let block) = item.content { return block.text }
            return nil
        }
        XCTAssertTrue(bodyTexts.contains("[polish] " + bodyBefore), "body text transformed")

        coordinator.revert(editor: editor)
        let restored = editor.items.compactMap { item -> String? in
            if case .text(let block) = item.content { return block.text }
            return nil
        }
        XCTAssertTrue(restored.contains(bodyBefore), "one-tap revert restores the original")
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testStopLeavesNoResidueAndRefillsPrompt() async {
        let editor = makeEditor()
        let coordinator = makeCoordinator(
            text: ScriptedText(delay: .seconds(3)),
            workingDelay: .milliseconds(5)
        )
        let itemsBefore = editor.items
        let undoBefore = editor.canUndo

        coordinator.ask("polish the text", editor: editor)
        await waitUntil { if case .working = coordinator.phase { return true } else { return false } }
        guard case .working(let verb) = coordinator.phase else {
            return XCTFail("expected working state")
        }
        XCTAssertEqual(verb, "Polishing the text...")
        XCTAssertFalse(coordinator.workingItemIDs.isEmpty, "affected element marked for breathing")

        coordinator.stop()
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.refillPrompt, "polish the text", "the words come back")
        XCTAssertEqual(editor.items, itemsBefore, "stop leaves no partial edits")
        XCTAssertEqual(editor.canUndo, undoBefore, "no orphaned undo snapshot")
        XCTAssertTrue(coordinator.workingItemIDs.isEmpty)
    }

    func testWorkingIndicatorWaitsForItsDelay() async {
        let coordinator = makeCoordinator(
            text: ScriptedText(delay: .milliseconds(400)),
            workingDelay: .milliseconds(150)
        )
        let editor = makeEditor()
        coordinator.ask("polish the text", editor: editor)

        try? await Task.sleep(for: .milliseconds(40))
        if case .working = coordinator.phase {
            XCTFail("working state must not appear before the 400ms-style threshold")
        }
        await waitUntil { if case .working = coordinator.phase { return true } else { return false } }
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
    }

    func testBackendFailureRefillsAndOffersRetry() async {
        let editor = makeEditor()
        let coordinator = makeCoordinator(chat: ScriptedChat(error: URLError(.notConnectedToInternet)))

        coordinator.ask("tell me something nice", editor: editor)
        await waitUntil { if case .failure = coordinator.phase { return true } else { return false } }

        guard case .failure(let failure) = coordinator.phase else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(failure.kind, .retry)
        XCTAssertTrue(failure.chips.contains("Try again"))
        XCTAssertEqual(coordinator.refillPrompt, "tell me something nice")
    }

    func testTimeoutBecomesARetryFailure() async {
        let editor = makeEditor()
        let coordinator = makeCoordinator(
            text: ScriptedText(delay: .seconds(10)),
            timeout: .milliseconds(60)
        )

        coordinator.ask("polish the text", editor: editor)
        await waitUntil { if case .failure = coordinator.phase { return true } else { return false } }

        guard case .failure(let failure) = coordinator.phase else {
            return XCTFail("expected timeout failure")
        }
        XCTAssertEqual(failure.kind, .retry)
        XCTAssertTrue(failure.message.contains("taking too long"))
    }

    func testConversationRepliesWithChipsAndCarriesSession() async {
        let editor = makeEditor()
        let chat = ScriptedChat(reply: "That sounds lovely.", sessionID: "s-42")
        let coordinator = makeCoordinator(chat: chat)

        coordinator.ask("hello mira", editor: editor)
        await waitUntil { if case .reply = coordinator.phase { return true } else { return false } }
        guard case .reply(let message, let chips) = coordinator.phase else {
            return XCTFail("expected reply")
        }
        XCTAssertEqual(message, "That sounds lovely.")
        XCTAssertFalse(chips.isEmpty, "reply offers follow-up chips")

        coordinator.ask("and another thing", editor: editor)
        await waitUntil { if case .reply = coordinator.phase { return true } else { return false } }
        let seen = await chat.recorder.sessionIDs
        XCTAssertEqual(seen, [nil, "s-42"], "server session id carries into the next turn")

        // Mira converses standing on the page: every turn sends it along.
        let sentNotes = await chat.recorder.notes
        XCTAssertEqual(sentNotes.count, 2)
        let page = ChatNote(page: editor.composedMemory())
        XCTAssertEqual(sentNotes.first, [page], "the current page grounds the conversation")
        XCTAssertFalse(page.title.isEmpty)
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
    }

    func testReplacingALiveTurnKeepsStopWorking() async {
        // Reviewer major: task A's defer must not null task B's handle.
        let editor = makeEditor()
        let coordinator = makeCoordinator(
            text: ScriptedText(delay: .seconds(3)),
            chat: ScriptedChat(delay: .seconds(3)),
            workingDelay: .milliseconds(5)
        )
        let itemsBefore = editor.items

        coordinator.ask("polish the text", editor: editor)
        try? await Task.sleep(for: .milliseconds(30))
        coordinator.ask("hello there mira", editor: editor)
        // Let turn A's cancellation unwind (its defer must not touch turn B).
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertTrue(coordinator.isWorking, "the replacing turn is still alive")
        coordinator.stop()
        XCTAssertEqual(coordinator.phase, .idle, "Stop still works after replacement")
        XCTAssertEqual(coordinator.refillPrompt, "hello there mira", "refill is turn B's words")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(editor.items, itemsBefore, "neither turn applied anything")
    }

    func testRevertDeclinesAfterAUserEdit() async {
        // Reviewer major: Revert must never eat the user's own edit.
        let editor = makeEditor()
        let coordinator = makeCoordinator()
        coordinator.ask("polish the text", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }

        // The user drags something while the receipt is up.
        editor.beginChange()
        let anyID = editor.items[0].id
        editor.move(itemID: anyID, to: CGPoint(x: 200, y: 200))
        let itemsAfterUserEdit = editor.items

        coordinator.revert(editor: editor)
        XCTAssertEqual(editor.items, itemsAfterUserEdit, "revert declines instead of undoing the drag")
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testReceiptStepsAsideWhenTheCanvasChanges() async {
        let editor = makeEditor()
        let coordinator = makeCoordinator()
        coordinator.ask("polish the text", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }

        editor.beginChange()
        coordinator.canvasDidChange(editor)
        XCTAssertEqual(coordinator.phase, .idle, "a user edit auto-keeps the receipt")
    }

    func testTransformWithNoTextAsksToClarify() async {
        let editor = CanvasViewModel(memory: Memory())
        let coordinator = makeCoordinator()

        coordinator.ask("polish the text", editor: editor)
        await waitUntil { if case .failure = coordinator.phase { return true } else { return false } }

        guard case .failure(let failure) = coordinator.phase else {
            return XCTFail("expected a clarify failure")
        }
        XCTAssertEqual(failure.kind, .clarify)
        XCTAssertTrue(failure.chips.contains("Add a soft title"))
    }

    func testComposedMemoryKeepsTitleWhenPageHasNoText() {
        // Opening and closing the editor must never rename a text-less page
        // (e.g. a chat-filed memory).
        let source = Memory(title: "a quiet morning", body: "kept body")
        let editor = CanvasViewModel(memory: source)
        let composed = editor.composedMemory()
        XCTAssertEqual(composed.title, "a quiet morning")
        XCTAssertEqual(composed.body, "kept body")
    }

    func testMaterializedLegacyPageRoundTripsTitleAndBody() {
        let legacy = Memory(title: "Slow morning, good coffee", body: "the kettle sang first")
        let opened = legacy.materializedForEditing()
        XCTAssertEqual(opened.items.count, 2, "title and body become canvas elements")

        let editor = CanvasViewModel(memory: opened)
        let composed = editor.composedMemory()
        XCTAssertEqual(composed.title, "Slow morning, good coffee")
        XCTAssertEqual(composed.body, "the kettle sang first")
        XCTAssertEqual(composed.id, legacy.id, "same page, no duplicate")

        let untouched = Memory(title: "has items already", items: Memory.starterDraft())
        XCTAssertEqual(untouched.materializedForEditing().items, untouched.items)
    }

    func testSuggestionsAreContextAware() {
        let coordinator = makeCoordinator()
        let empty = CanvasViewModel(memory: Memory())
        XCTAssertEqual(coordinator.suggestions(for: empty), [], "a blank page has nothing to suggest about")

        let soundOnly = CanvasViewModel(memory: Memory())
        _ = soundOnly.addSound(SoundClip(duration: 3, note: "birds"), at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(
            coordinator.suggestions(for: soundOnly), [],
            "a title is about words -- it must not pop right after a sound"
        )

        let wordsNoTitle = CanvasViewModel(memory: Memory())
        _ = wordsNoTitle.addText("small words", at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(
            coordinator.suggestions(for: wordsNoTitle),
            ["Polish the text", "Add a soft title"]
        )

        let full = makeEditor()
        XCTAssertEqual(
            coordinator.suggestions(for: full),
            ["Polish the text", "Tidy the layout"],
            "no title chip when the page already has a display-size title"
        )
    }
}

// MARK: - Scripted services

private struct ScriptedText: TextTransformService {
    var delay: Duration = .zero
    var error: Error?

    func transform(_ text: String, mode: TextTransformMode) async throws -> String {
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return "[\(mode.rawValue)] " + text
    }
}

private struct ScriptedChat: ChatService {
    var reply = "Scripted reply."
    var sessionID: String? = "scripted-session"
    var delay: Duration = .zero
    var error: Error?
    let recorder = SessionRecorder()

    func reply(to message: String, sessionID incoming: String?, notes: [ChatNote]) async throws -> ChatReply {
        await recorder.record(incoming, notes: notes)
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return ChatReply(text: reply, sessionID: sessionID)
    }
}

private actor SessionRecorder {
    private(set) var sessionIDs: [String?] = []
    private(set) var notes: [[ChatNote]] = []

    func record(_ id: String?, notes incoming: [ChatNote]) {
        sessionIDs.append(id)
        notes.append(incoming)
    }
}
