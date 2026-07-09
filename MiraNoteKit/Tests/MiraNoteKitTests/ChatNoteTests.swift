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
