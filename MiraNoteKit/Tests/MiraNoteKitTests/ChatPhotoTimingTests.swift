import XCTest
@testable import MiraNoteKit

/// Chat photos never hold a turn hostage: descriptions run together under
/// a short cap (like the canvas's 8 s), Send waits for picks still loading,
/// and a pick that fails to load says so.
@MainActor
final class ChatPhotoTimingTests: XCTestCase {
    private var imageDirectory: URL!

    override func setUp() {
        super.setUp()
        imageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatPhotoTimingTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: imageDirectory)
        super.tearDown()
    }

    private func makeViewModel(
        chat: MessageCapturingChat = MessageCapturingChat(),
        studio: ImageStudioService,
        describeTimeout: Duration? = nil
    ) -> ChatViewModel {
        let store = ImageFileStore(directory: imageDirectory)
        if let describeTimeout {
            return ChatViewModel(
                service: chat, studio: studio, transcription: MockVoiceTranscriptionService(),
                makeRecorder: { MockAudioRecorder() }, imageStore: store, describeTimeout: describeTimeout
            )
        }
        return ChatViewModel(
            service: chat, studio: studio, transcription: MockVoiceTranscriptionService(),
            makeRecorder: { MockAudioRecorder() }, imageStore: store
        )
    }

    func testPhotosAreDescribedTogetherInPickOrder() async {
        let chat = MessageCapturingChat()
        let viewModel = makeViewModel(chat: chat, studio: SlowDescribingStudio(delay: .milliseconds(400)))
        for byte in 1...3 { viewModel.stageImage(Data([UInt8(byte)])) }

        let started = ContinuousClock.now
        await viewModel.sendDraft()
        let elapsed = ContinuousClock.now - started

        XCTAssertLessThan(elapsed, .milliseconds(1_000), "three 400 ms looks run side by side, not 1.2 s in a row")
        let sent = await chat.messages.all
        XCTAssertEqual(sent, ["(photo) photo 1\n(photo) photo 2\n(photo) photo 3"])
    }

    func testASlowImageServiceIsCutOffAndSaysSo() async {
        let chat = MessageCapturingChat()
        let viewModel = makeViewModel(
            chat: chat, studio: SlowDescribingStudio(delay: .seconds(30)), describeTimeout: .milliseconds(300)
        )
        for byte in 1...4 { viewModel.stageImage(Data([UInt8(byte)])) }
        viewModel.draft = "what is this?"

        let started = ContinuousClock.now
        await viewModel.sendDraft()
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3), "the cap, not 4 x the service's time")

        let unseen = "(photo) a photo Mira could not look at"
        let sent = await chat.messages.all
        XCTAssertEqual(sent, [[unseen, unseen, unseen, unseen, "what is this?"].joined(separator: "\n")])
        XCTAssertEqual(viewModel.hint, .photoUnseen)
    }

    func testSendWaitsForPicksStillLoading() async {
        let viewModel = makeViewModel(studio: MockImageStudioService())
        viewModel.draft = "with a photo"
        let loading = Task {
            await viewModel.stagePhotos([{
                try? await Task.sleep(for: .milliseconds(300))
                return MockImageStudioService.tinyPNG
            }])
        }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.loadingImages, 1)
        XCTAssertFalse(viewModel.canSend, "the photo would miss this message")

        await loading.value
        XCTAssertEqual(viewModel.loadingImages, 0)
        XCTAssertEqual(viewModel.stagedImages.count, 1)
        XCTAssertTrue(viewModel.canSend)
    }

    func testAPickThatFailsToLoadSaysSo() async {
        let viewModel = makeViewModel(studio: MockImageStudioService())
        await viewModel.stagePhotos([{ nil }, { MockImageStudioService.tinyPNG }])
        XCTAssertEqual(viewModel.stagedImages.count, 1, "the one that loaded is staged")
        XCTAssertEqual(viewModel.hint, .photoNotLoaded)
    }

    func testLoadingPicksCountTowardTheFour() async {
        let viewModel = makeViewModel(studio: MockImageStudioService())
        for byte in 0..<3 { viewModel.stageImage(Data([UInt8(byte)])) }
        let loading = Task {
            await viewModel.stagePhotos([{
                try? await Task.sleep(for: .milliseconds(200))
                return MockImageStudioService.tinyPNG
            }])
        }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(viewModel.canStageMoreImages)
        await loading.value
    }
}

/// Describes each photo as "photo <first byte>" after `delay`.
private struct SlowDescribingStudio: ImageStudioService {
    let delay: Duration

    func describe(image: Data) async throws -> String {
        try await Task.sleep(for: delay)
        return "photo \(image.first ?? 0)"
    }
    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] { [] }
    func cutout(image: Data, target: String?) async throws -> Data { image }
    func stylize(image: Data, instruction: String) async throws -> Data { image }
    func outline(image: Data) async throws -> Data { image }
}
