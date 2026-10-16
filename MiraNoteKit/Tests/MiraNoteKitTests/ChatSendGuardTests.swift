import XCTest
@testable import MiraNoteKit

/// What a chat message takes with it and leaves behind: one message at a
/// time, page searches only with words someone said or saw, and no sent
/// photos left in tmp once the chat closes.
@MainActor
final class ChatSendGuardTests: XCTestCase {
    private var imageDirectory: URL!

    override func setUp() {
        super.setUp()
        imageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatSendGuardTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: imageDirectory)
        super.tearDown()
    }

    private func makeViewModel(
        chat: ChatService = MessageCapturingChat(),
        studio: ImageStudioService = MockImageStudioService(),
        notes: @escaping (String) -> [ChatNote] = { _ in [] }
    ) -> ChatViewModel {
        ChatViewModel(
            service: chat, studio: studio, transcription: MockVoiceTranscriptionService(),
            makeRecorder: { MockAudioRecorder() }, imageStore: ImageFileStore(directory: imageDirectory),
            describeTimeout: .milliseconds(300), notesForMessage: notes
        )
    }

    func testAPhotoMiraCouldNotSeeSearchesNoPagesWithTheAppsOwnWords() async {
        var queries: [String] = []
        let viewModel = makeViewModel(studio: UnseeingStudio(), notes: { queries.append($0); return [] })
        viewModel.stageImage(MockImageStudioService.tinyPNG)
        await viewModel.sendDraft()
        XCTAssertFalse(queries.contains { $0.contains("could not look at") }, "queries: \(queries)")
    }

    func testAPhotoOnlyMessageSearchesWithWhatThePhotoShows() async {
        var queries: [String] = []
        let viewModel = makeViewModel(notes: { queries.append($0); return [] })
        viewModel.stageImage(MockImageStudioService.tinyPNG)
        await viewModel.sendDraft()
        let summary = (try? await MockImageStudioService().describe(image: MockImageStudioService.tinyPNG)) ?? ""
        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(queries, [summary])
    }

    func testASecondSendWhileMiraAnswersIsHeld() async {
        let chat = SlowChat()
        let viewModel = makeViewModel(chat: chat)
        let first = Task { await viewModel.send("first") }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(viewModel.isResponding)
        await viewModel.send("Rewrite softer")
        await first.value
        let sent = await chat.log.all
        XCTAssertEqual(sent, ["first"], "a second message went out mid-answer")
    }

    func testClosingTheChatDeletesTheSentPhotos() async throws {
        let viewModel = makeViewModel()
        viewModel.stageImage(MockImageStudioService.tinyPNG)
        viewModel.draft = "look"
        await viewModel.sendDraft()
        let store = ImageFileStore(directory: imageDirectory)
        let fileName = try XCTUnwrap(viewModel.messages.first?.imageFileNames.first)
        XCTAssertTrue(store.exists(fileName: fileName))

        viewModel.discardSentPhotos()
        XCTAssertFalse(store.exists(fileName: fileName), "the sent photo is gone from tmp")
    }
}

private struct UnseeingStudio: ImageStudioService {
    func describe(image: Data) async throws -> String { throw URLError(.notConnectedToInternet) }
    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] { [] }
    func cutout(image: Data, target: String?) async throws -> Data { image }
    func stylize(image: Data, instruction: String) async throws -> Data { image }
    func outline(image: Data) async throws -> Data { image }
}

private struct SlowChat: ChatService {
    let log = MessageLog()

    func reply(
        to message: String, sessionID: String?,
        notes: [ChatNote], page: PageContext?
    ) async throws -> ChatReply {
        await log.record(message)
        try? await Task.sleep(for: .milliseconds(300))
        return ChatReply(text: "ok", sessionID: "s")
    }
}
