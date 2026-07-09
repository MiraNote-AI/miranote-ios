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
