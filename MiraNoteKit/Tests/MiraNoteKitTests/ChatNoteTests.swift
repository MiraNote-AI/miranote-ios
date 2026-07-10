import XCTest
@testable import MiraNoteKit

@MainActor
final class ChatNoteTests: XCTestCase {
    func testPageFlattensWordsAndSoundNotes() {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText("warm broth, golden light", at: CGPoint(x: 10, y: 10))
        _ = editor.addSound(SoundClip(duration: 2, note: "street sounds"), at: CGPoint(x: 20, y: 20))
        var page = editor.composedMemory()
        page.memoryDate = Calendar.current.date(
            from: DateComponents(year: 2026, month: 6, day: 30)
        )!

        let note = ChatNote(page: page)
        XCTAssertEqual(note.title, "warm broth, golden light")
        XCTAssertTrue(note.body.contains("warm broth"))
        XCTAssertTrue(note.body.contains("(sound) street sounds"))
        XCTAssertEqual(note.date, "2026-06-30")
    }

    func testPageNoteMentionsPhotos() {
        let editor = CanvasViewModel(memory: Memory())
        editor.addImages([ImageRef(displayName: "Library photo")], around: .zero)
        let note = ChatNote(page: editor.composedMemory())
        XCTAssertTrue(
            note.body.contains("(photo) a photo Mira has not looked at yet"),
            "an unseen photo says so -- names like Library photo mislead the model"
        )
    }

    func testPageNotePrefersTheVisionSummary() {
        let editor = CanvasViewModel(memory: Memory())
        let ids = editor.addImages([ImageRef(displayName: "Library photo")], around: .zero)
        editor.setImageSummary(itemID: ids[0], to: "a field of fuchsia ice plants in bloom")
        let note = ChatNote(page: editor.composedMemory())
        XCTAssertTrue(
            note.body.contains("(photo) a field of fuchsia ice plants in bloom"),
            "once vision has seen the photo, chat sees what vision saw"
        )
        XCTAssertFalse(editor.canUndo && note.body.isEmpty, "summary writes burn no undo step")
    }

    func testReplyStepsAsideWhenTheCanvasChanges() async {
        let editor = CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
        let coordinator = MiraCanvasCoordinator(
            text: ScriptedText(),
            chat: ScriptedChat(),
            workingDelay: .milliseconds(1),
            timeout: .seconds(5),
            receiptDismiss: .seconds(60)
        )
        coordinator.ask("hello mira", editor: editor)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if case .reply = coordinator.phase { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard case .reply = coordinator.phase else { return XCTFail("expected a reply") }

        _ = editor.addText("back to making things", at: CGPoint(x: 100, y: 100))
        coordinator.canvasDidChange(editor)
        XCTAssertEqual(coordinator.phase, .idle, "a lingering reply steps aside on canvas edits")
    }

    func testReplaceImageFileSwapsPixelsClearsFilterUndoably() {
        let editor = CanvasViewModel(memory: Memory())
        editor.addImages([ImageRef(displayName: "bird", fileName: "old.png")], around: .zero)
        let id = editor.items[0].id
        editor.setImageFilter(itemID: id, to: "warm")

        editor.replaceImageFile(itemID: id, fileName: "edited.png")

        guard case .image(let ref) = editor.item(id)?.content else { return XCTFail("image gone") }
        XCTAssertEqual(ref.fileName, "edited.png")
        XCTAssertEqual(ref.filterName, "", "the AI result IS the look; stale filters clear")

        editor.undo()
        guard case .image(let back) = editor.item(id)?.content else { return XCTFail("image gone") }
        XCTAssertEqual(back.fileName, "old.png", "one undo step brings the old pixels back")
        XCTAssertEqual(back.filterName, "warm")
    }

    func testPlaceReplyLandsTheWordsWithAReceipt() async {
        let editor = CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
        let coordinator = MiraCanvasCoordinator(
            text: ScriptedText(),
            chat: ScriptedChat(),
            workingDelay: .milliseconds(1),
            timeout: .seconds(5),
            receiptDismiss: .seconds(60)
        )
        coordinator.ask("hello mira", editor: editor)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if case .reply = coordinator.phase { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard case .reply(_, let chips) = coordinator.phase else { return XCTFail("expected reply") }
        XCTAssertEqual(chips.first, MiraCanvasCoordinator.placeReplyChip)
        XCTAssertEqual(coordinator.conversation.count, 2, "the thread remembers the turn")

        let countBefore = editor.items.count
        coordinator.placeReply(editor: editor)
        XCTAssertEqual(editor.items.count, countBefore + 1, "the reply landed as a block")
        guard case .receipt(let receipt) = coordinator.phase else { return XCTFail("expected receipt") }
        XCTAssertEqual(receipt.changed, "Added a few words.")
    }

    func testCleanPlacedTextStripsMarkdownAndExtractsTheQuote() {
        let chatty = """
        How about this caption for the photo?

        > *"A single yellow leaf catches the light, standing apart from the green."*

        If you'd like, I can save it as a new note draft -- just say the word!
        """
        XCTAssertEqual(
            MiraIntent.cleanPlacedText(chatty),
            "A single yellow leaf catches the light, standing apart from the green.",
            "the quoted suggestion is the payload; the chatter stays in chat"
        )
        XCTAssertEqual(
            MiraIntent.cleanPlacedText("> **bold** and _soft_ words"),
            "bold and soft words"
        )
        XCTAssertEqual(
            MiraIntent.cleanPlacedText("Plain words, nothing framed."),
            "Plain words, nothing framed."
        )
    }

    func testCleanTitleStripsLLMNoise() {
        XCTAssertEqual(MiraIntent.cleanTitle("\"Ramen by the bridge.\"\nHope you like it!"),
                       "Ramen by the bridge")
        XCTAssertEqual(MiraIntent.cleanTitle("  A quiet moment  "), "A quiet moment")
        XCTAssertEqual(MiraIntent.cleanTitle(""), "")
        XCTAssertEqual(MiraIntent.cleanTitle(String(repeating: "long ", count: 30)).count <= 60, true)
    }

    func testReceiptDefaultOutlivesACarefulRead() {
        XCTAssertEqual(
            MiraCanvasCoordinator.defaultReceiptDismiss, .seconds(6),
            "one line plus inline Revert reads in six; header undo covers the rest"
        )
    }

    func testMaterializedDraftBodyHugsTheTitle() {
        let draft = Memory(title: "Drafted by Mira", body: "warm broth").materializedForEditing()
        XCTAssertEqual(draft.items.count, 2)
        let title = draft.items[0]
        let body = draft.items[1]
        let titleBottom = title.position.y + title.size.height / 2
        let bodyTop = body.position.y - body.size.height / 2
        XCTAssertEqual(bodyTop - titleBottom, 12, accuracy: 0.5,
                       "a drafted page reads as one composition, not two islands")
    }

    func testMaterializedLongTitleStillClearsTheBody() {
        let draft = Memory(
            title: "Ramen by the bridge with Jason on a warm evening",
            body: String(repeating: "the broth stayed with us. ", count: 8)
        ).materializedForEditing()
        let title = draft.items[0]
        let body = draft.items[1]
        XCTAssertGreaterThan(title.size.height, 60, "two estimated lines")
        XCTAssertGreaterThanOrEqual(
            body.position.y - body.size.height / 2,
            title.position.y + title.size.height / 2,
            "estimated heights chain -- blocks never overlap"
        )
    }

    func testSendCarriesTheMatchingPages() async {
        let chat = CapturingChat()
        let viewModel = ChatViewModel(service: chat) { message in
            [ChatNote(title: "hit for " + message, body: "", date: "")]
        }

        await viewModel.send("noodles")

        let sent = await chat.recorder.all
        XCTAssertEqual(sent, [[ChatNote(title: "hit for noodles", body: "", date: "")]])
    }
}

private struct CapturingChat: ChatService {
    let recorder = NotesRecorder()

    func reply(to message: String, sessionID: String?, notes: [ChatNote]) async throws -> ChatReply {
        await recorder.record(notes)
        return ChatReply(text: "ok", sessionID: "s")
    }
}

private actor NotesRecorder {
    private(set) var all: [[ChatNote]] = []

    func record(_ notes: [ChatNote]) {
        all.append(notes)
    }
}
