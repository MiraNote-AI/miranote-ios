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
        describeTimeout: Duration = .seconds(8),
        pickTimeout: Duration = .seconds(20)
    ) -> ChatViewModel {
        ChatViewModel(
            service: chat, studio: studio, transcription: MockVoiceTranscriptionService(),
            makeRecorder: { MockAudioRecorder() }, imageStore: ImageFileStore(directory: imageDirectory),
            describeTimeout: describeTimeout, pickTimeout: pickTimeout
        )
    }

    /// A pick that never finishes loading (an iCloud original, offline).
    private let stuckPick: @Sendable () async -> Data? = {
        try? await Task.sleep(for: .seconds(3600))
        return nil
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

    func testAStuckPickTimesOutIntoTheFailedPickNotice() async {
        let viewModel = makeViewModel(studio: MockImageStudioService(), pickTimeout: .milliseconds(300))
        viewModel.draft = "hello"
        let loading = Task { await viewModel.stagePhotos([stuckPick]) }
        defer { loading.cancel() }
        try? await Task.sleep(for: .seconds(1))
        XCTAssertEqual(viewModel.loadingImages, 0, "the pick gave up at its timeout")
        XCTAssertEqual(viewModel.hint, .photoNotLoaded)
        XCTAssertTrue(viewModel.canSend, "the typed words can go")
    }

    func testRemovingAStuckFirstPickStagesTheLoadedOneBehindIt() async throws {
        let viewModel = makeViewModel(studio: MockImageStudioService())
        let quick: @Sendable () async -> Data? = { Data([2]) }
        let loading = Task { await viewModel.stagePhotos([stuckPick, quick]) }
        defer { loading.cancel() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(viewModel.stagedImages.isEmpty, "the second waits its turn behind the first")
        let first = try XCTUnwrap(viewModel.loadingPicks.first)
        viewModel.removeLoadingPick(first)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(viewModel.stagedImages, [Data([2])], "the loaded second pick is still held behind the removed one")
        XCTAssertEqual(viewModel.loadingImages, 0, "Send still held")
    }

    /// A loader that does not observe cancellation: the timeout still frees
    /// Send on time, without waiting for the loader to give up.
    func testTheTimeoutHoldsForALoaderThatIgnoresCancellation() async throws {
        let viewModel = makeViewModel(studio: MockImageStudioService(), pickTimeout: .milliseconds(300))
        let deaf: @Sendable () async -> Data? = {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) { continuation.resume() }
            }
            return nil
        }
        viewModel.draft = "hello"
        let loading = Task { await viewModel.stagePhotos([deaf]) }
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertEqual(viewModel.loadingImages, 0, "still loading 1.2 s after a 0.3 s timeout")
        XCTAssertEqual(viewModel.hint, .photoNotLoaded)
        XCTAssertTrue(viewModel.canSend)
        await loading.value
    }

    func testRemovingALoadingPickFreesSendAndDropsItsLateResult() async throws {
        let viewModel = makeViewModel(studio: MockImageStudioService())
        viewModel.draft = "hello"
        let loading = Task {
            await viewModel.stagePhotos([{
                try? await Task.sleep(for: .milliseconds(300))
                return MockImageStudioService.tinyPNG
            }])
        }
        try? await Task.sleep(for: .milliseconds(50))
        let pick = try XCTUnwrap(viewModel.loadingPicks.first, "the pick shows as loading")
        viewModel.removeLoadingPick(pick)
        XCTAssertEqual(viewModel.loadingImages, 0)
        XCTAssertTrue(viewModel.canSend, "nothing holds Send any more")

        await loading.value
        XCTAssertTrue(viewModel.stagedImages.isEmpty, "the removed pick does not come back when it loads")
        XCTAssertNil(viewModel.hint, "and is not reported as failed")
    }

    func testPicksLoadSideBySideInPickOrder() async {
        let viewModel = makeViewModel(studio: MockImageStudioService())
        let loaders: [@Sendable () async -> Data?] = (1...4).map { byte in
            {
                // The first pick is the slowest: order is the pick's, not the arrival's.
                try? await Task.sleep(for: .milliseconds(400 - byte * 50))
                return Data([UInt8(byte)])
            }
        }
        let started = ContinuousClock.now
        await viewModel.stagePhotos(loaders)
        XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(800), "four loads run together, not in a row")
        XCTAssertEqual(viewModel.stagedImages, (1...4).map { Data([UInt8($0)]) })
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
