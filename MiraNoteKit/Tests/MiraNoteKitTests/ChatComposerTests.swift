import XCTest
@testable import MiraNoteKit

/// The chat composer's voice and photo paths: dictation fills the draft (it
/// is never sent on release) and staged photos ride with the message as
/// their descriptions, since the chat backend is text-only.
@MainActor
final class ChatComposerTests: XCTestCase {
    private var imageDirectory: URL!

    override func setUp() {
        super.setUp()
        imageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatComposerTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: imageDirectory)
        super.tearDown()
    }

    private func makeViewModel(
        chat: MessageCapturingChat = MessageCapturingChat(),
        studio: ImageStudioService = MockImageStudioService(),
        transcription: VoiceTranscriptionService = MockVoiceTranscriptionService(),
        recorder: @escaping @MainActor () -> AudioRecording = { MockAudioRecorder() }
    ) -> ChatViewModel {
        ChatViewModel(
            service: chat, studio: studio, transcription: transcription,
            makeRecorder: recorder, imageStore: ImageFileStore(directory: imageDirectory)
        )
    }

    // MARK: - Staging

    func testAStagedPhotoAloneCanBeSent() {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.canSend)
        viewModel.stageImage(MockImageStudioService.tinyPNG)
        XCTAssertTrue(viewModel.canSend, "a photo is a message even with no words")
    }

    func testStagingStopsAtFourAndRemovesByIndex() {
        let viewModel = makeViewModel()
        for byte in 0..<6 { viewModel.stageImage(Data([UInt8(byte)])) }
        XCTAssertEqual(viewModel.stagedImages.count, ChatViewModel.maxStagedImages)
        XCTAssertFalse(viewModel.canStageMoreImages)

        viewModel.removeStagedImage(at: 1)
        XCTAssertEqual(viewModel.stagedImages, [Data([0]), Data([2]), Data([3])])
        viewModel.removeStagedImage(at: 9)
        XCTAssertEqual(viewModel.stagedImages.count, 3, "an out-of-range remove is ignored")
    }

    // MARK: - Sending photos

    func testPhotoDescriptionPrefixesTheMessage() async {
        let chat = MessageCapturingChat()
        let viewModel = makeViewModel(chat: chat, studio: DescribingStudio(result: .success("a bowl of ramen")))
        viewModel.stageImage(MockImageStudioService.tinyPNG)
        viewModel.draft = "what should I write about this?"

        await viewModel.sendDraft()

        let sent = await chat.messages.all
        XCTAssertEqual(sent, ["(photo) a bowl of ramen\nwhat should I write about this?"])
        XCTAssertTrue(viewModel.stagedImages.isEmpty)
        XCTAssertEqual(viewModel.draft, "")
        XCTAssertNil(viewModel.hint)
    }

    func testTheBubbleKeepsTheUsersWordsAndThePhoto() async {
        let viewModel = makeViewModel(studio: DescribingStudio(result: .success("a bowl of ramen")))
        viewModel.stageImage(MockImageStudioService.tinyPNG)
        viewModel.draft = "look"

        await viewModel.sendDraft()

        let user = viewModel.messages.first { $0.role == .user }
        XCTAssertEqual(user?.text, "look", "the description is for Mira, not the bubble")
        XCTAssertEqual(user?.imageFileNames.count, 1)
        let stored = user?.imageFileNames.first.flatMap {
            ImageFileStore(directory: imageDirectory).data(forFileName: $0)
        }
        XCTAssertEqual(stored, MockImageStudioService.tinyPNG)
    }

    func testAPhotoWithNoWordsSendsItsDescription() async {
        let chat = MessageCapturingChat()
        let viewModel = makeViewModel(chat: chat, studio: DescribingStudio(result: .success("a sunset")))
        viewModel.stageImage(MockImageStudioService.tinyPNG)
        viewModel.stageImage(MockImageStudioService.tinyPNG)

        await viewModel.sendDraft()

        let sent = await chat.messages.all
        XCTAssertEqual(sent, ["(photo) a sunset\n(photo) a sunset"])
    }

    func testAFailedDescribeStillSendsTheWordsAndSaysSo() async {
        let chat = MessageCapturingChat()
        let viewModel = makeViewModel(chat: chat, studio: DescribingStudio(result: .failure(URLError(.timedOut))))
        viewModel.stageImage(MockImageStudioService.tinyPNG)
        viewModel.draft = "hello"

        await viewModel.sendDraft()

        let sent = await chat.messages.all
        XCTAssertEqual(sent, ["(photo) a photo Mira could not look at\nhello"])
        XCTAssertEqual(viewModel.hint, .photoUnseen)
        XCTAssertEqual(viewModel.messages.last?.role, .assistant, "Mira still answered")
    }

    // MARK: - Voice

    func testTranscriptFillsAnEmptyDraft() {
        let viewModel = makeViewModel()
        XCTAssertTrue(viewModel.insertTranscript("  a quiet morning  "))
        XCTAssertEqual(viewModel.draft, "a quiet morning")
    }

    func testTranscriptAppendsAfterTypedWords() {
        let viewModel = makeViewModel()
        viewModel.draft = "Today"
        viewModel.insertTranscript("was slow")
        XCTAssertEqual(viewModel.draft, "Today was slow")
    }

    func testAnEmptyTranscriptChangesNothing() {
        let viewModel = makeViewModel()
        viewModel.draft = "keep me"
        XCTAssertFalse(viewModel.insertTranscript("   "))
        XCTAssertEqual(viewModel.draft, "keep me")
    }

    func testHoldThenReleaseFillsTheFieldAndSendsNothing() async {
        let chat = MessageCapturingChat()
        let viewModel = makeViewModel(chat: chat, transcription: FixedTranscription(text: "noodles by the bridge"))

        viewModel.startVoice()
        guard case .recording = viewModel.voice else { return XCTFail("recording after press") }
        await viewModel.finishVoice()

        XCTAssertEqual(viewModel.draft, "noodles by the bridge")
        XCTAssertEqual(viewModel.voice, .idle)
        XCTAssertTrue(viewModel.messages.isEmpty, "voice-to-text, not auto-send")
        let sent = await chat.messages.all
        XCTAssertTrue(sent.isEmpty)
    }

    func testSilenceSaysNoWordsWereCaught() async {
        let viewModel = makeViewModel(transcription: FixedTranscription(text: " "))
        viewModel.startVoice()
        await viewModel.finishVoice()
        XCTAssertEqual(viewModel.hint, .noWords)
        XCTAssertEqual(viewModel.draft, "")
    }

    func testMicDeniedPointsAtSettings() async {
        let viewModel = makeViewModel(recorder: { DeniedRecorder() })
        viewModel.startVoice()
        await viewModel.finishVoice()
        XCTAssertEqual(viewModel.hint?.opensSettings, true)
        XCTAssertEqual(viewModel.hint?.text, RecordingError.microphonePermissionDenied.errorDescription)
        XCTAssertEqual(viewModel.voice, .idle)
    }

    func testCancelKeepsNothing() async {
        let viewModel = makeViewModel(transcription: FixedTranscription(text: "should not land"))
        viewModel.startVoice()
        viewModel.cancelVoice()
        await viewModel.finishVoice()
        XCTAssertEqual(viewModel.voice, .idle)
        XCTAssertEqual(viewModel.draft, "")
        XCTAssertNil(viewModel.hint)
    }
}

struct MessageCapturingChat: ChatService {
    let messages = MessageLog()

    func reply(
        to message: String, sessionID: String?,
        notes: [ChatNote], page: PageContext?
    ) async throws -> ChatReply {
        await messages.record(message)
        return ChatReply(text: "ok", sessionID: "s")
    }
}

actor MessageLog {
    private(set) var all: [String] = []

    func record(_ message: String) {
        all.append(message)
    }
}

private struct DescribingStudio: ImageStudioService {
    let result: Result<String, Error>

    func describe(image: Data) async throws -> String { try result.get() }
    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] { [] }
    func cutout(image: Data, target: String?) async throws -> Data { image }
    func stylize(image: Data, instruction: String) async throws -> Data { image }
    func outline(image: Data) async throws -> Data { image }
}

private struct FixedTranscription: VoiceTranscriptionService {
    let text: String

    func transcribe(audio: Data, filename: String) async throws -> String { text }
}

@MainActor
private final class DeniedRecorder: AudioRecording {
    var isRecording: Bool { false }
    var level: Float { 0 }
    func start() async throws { throw RecordingError.microphonePermissionDenied }
    func stop() async throws -> Data { Data() }
}
