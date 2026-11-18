import XCTest
@testable import MiraNoteKit

/// #151: the stored AI consent, the mood switch, and the services that
/// ask before anything leaves the phone.
@MainActor
final class AIConsentTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ai-consent-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// `present` answers at once with `answer`, counting the sheets shown.
    private func consent(answering answer: Bool, shown: @escaping () -> Void = {}) -> AIConsent {
        let consent = AIConsent(defaults: defaults)
        consent.present = { [unowned consent] in
            shown()
            Task { @MainActor in consent.answer(answer) }
        }
        return consent
    }

    /// The `AIConsentError` `body` throws, nil when it goes through.
    private func refusal(_ body: () async throws -> Void) async -> AIConsentError? {
        do {
            try await body()
            return nil
        } catch {
            return error as? AIConsentError
        }
    }

    // MARK: Stored state

    func testAFreshInstallHasNotAgreedAndReadsMoodsOnceItDoes() {
        let consent = AIConsent(defaults: defaults)
        XCTAssertFalse(consent.isGranted)
        XCTAssertTrue(consent.moodFromWords, "the mood switch is on by default")
        XCTAssertFalse(consent.allowsMood, "but nothing is read before consent")
    }

    func testContinueIsKeptAcrossLaunches() async {
        let granted = await consent(answering: true).permit()
        XCTAssertTrue(granted)
        XCTAssertTrue(AIConsent(defaults: defaults).isGranted)
        XCTAssertTrue(AIConsent(defaults: defaults).allowsMood)
    }

    func testNotNowIsNotKept() async {
        var sheets = 0
        let consent = consent(answering: false, shown: { sheets += 1 })
        let first = await consent.permit()
        let second = await consent.permit()
        XCTAssertFalse(first)
        XCTAssertFalse(second)
        XCTAssertEqual(sheets, 2, "Not now: the next action asks again")
        XCTAssertFalse(AIConsent(defaults: defaults).isGranted)
    }

    func testGrantedAsksNothing() async {
        var sheets = 0
        let consent = consent(answering: true, shown: { sheets += 1 })
        _ = await consent.permit()
        _ = await consent.permit()
        XCTAssertEqual(sheets, 1, "the sheet never shows again")
    }

    func testWithdrawAsksAgainAndIsKept() async {
        var sheets = 0
        let consent = consent(answering: true, shown: { sheets += 1 })
        _ = await consent.permit()
        consent.withdraw()
        XCTAssertFalse(AIConsent(defaults: defaults).isGranted, "withdrawn across a relaunch")
        XCTAssertFalse(consent.allowsMood)
        _ = await consent.permit()
        XCTAssertEqual(sheets, 2)
    }

    func testMoodSwitchIsKeptAndNeedsConsent() async {
        let consent = consent(answering: true)
        consent.moodFromWords = false
        _ = await consent.permit()
        XCTAssertFalse(consent.allowsMood)
        XCTAssertFalse(AIConsent(defaults: defaults).moodFromWords)
        consent.moodFromWords = true
        XCTAssertTrue(AIConsent(defaults: defaults).allowsMood)
    }

    func testGrantedByDefaultIsOnlyADefault() {
        XCTAssertTrue(AIConsent(defaults: defaults, grantedByDefault: true).isGranted)
        AIConsent(defaults: defaults, grantedByDefault: true).withdraw()
        XCTAssertFalse(AIConsent(defaults: defaults, grantedByDefault: true).isGranted,
                       "a stored withdrawal wins over the default")
    }

    func testNoPresenterSendsNothing() async {
        let consent = AIConsent(defaults: defaults)
        let granted = await consent.permit()
        XCTAssertFalse(granted)
    }

    func testRequestsWaitingTogetherShareOneSheet() async {
        var sheets = 0
        let consent = AIConsent(defaults: defaults)
        consent.present = { sheets += 1 }
        async let first = consent.permit()
        async let second = consent.permit()
        while !consent.isAsking { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
        consent.answer(true)
        let answers = await [first, second]
        XCTAssertEqual(answers, [true, true])
        XCTAssertEqual(sheets, 1)
        XCTAssertFalse(consent.isAsking)
    }

    // MARK: Services that ask

    func testNotNowSendsNothing() async {
        let text = CountingTextTransform()
        let services = ServiceContainer.mock.replacingText(text).asking(consent(answering: false))
        do {
            _ = try await services.textTransform.transform("hi", mode: .polish)
            XCTFail("Not now: no result")
        } catch {
            XCTAssertEqual(error as? AIConsentError, .notNow)
        }
        let calls = await text.calls
        XCTAssertEqual(calls, 0)
    }

    func testContinueSendsAndCounts() async throws {
        let text = CountingTextTransform()
        let consent = consent(answering: true)
        let services = ServiceContainer.mock.replacingText(text).asking(consent)
        _ = try await services.textTransform.transform("hi", mode: .polish)
        _ = try await services.textTransform.transform("hi", mode: .clean)
        let calls = await text.calls
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(consent.sentRequests, 2)
    }

    func testMoodAndDescribeNeverShowTheSheet() async {
        var sheets = 0
        let services = ServiceContainer.mock.asking(consent(answering: true, shown: { sheets += 1 }))
        let mood = try? await services.mood.mood(for: "a happy day")
        let summary = try? await services.imageStudio.describe(image: MockImageStudioService.tinyPNG)
        XCTAssertNil(mood)
        XCTAssertNil(summary)
        XCTAssertEqual(sheets, 0, "background work waits for consent, it never asks")
    }

    func testMoodSwitchOffSendsNoMood() async throws {
        let consent = consent(answering: true)
        _ = await consent.permit()
        consent.moodFromWords = false
        let services = ServiceContainer.mock.asking(consent)
        let mood = try? await services.mood.mood(for: "a happy day")
        XCTAssertNil(mood)
        consent.moodFromWords = true
        let joyful = try await services.mood.mood(for: "a happy day")
        XCTAssertEqual(joyful, .joyful)
    }

    func testOnPhoneCutoutAndOutlineDoNotAsk() async throws {
        var sheets = 0
        let services = ServiceContainer.mock.asking(consent(answering: false, shown: { sheets += 1 }))
        let image = MockImageStudioService.tinyPNG
        _ = try await services.imageStudio.cutout(image: image, target: nil)
        _ = try await services.imageStudio.outline(image: image)
        XCTAssertEqual(sheets, 0)
        let named = try? await services.imageStudio.cutout(image: image, target: "dog")
        XCTAssertNil(named, "a named cutout goes to the server: it asks")
        XCTAssertEqual(sheets, 1)
    }

    func testAskToSendAsksOnceAndPlainServicesSayYes() async {
        var sheets = 0
        let consent = consent(answering: false, shown: { sheets += 1 })
        let services = ServiceContainer.mock.asking(consent)
        let voice = await refusal { try await services.voiceTranscription.askToSend() }
        let chat = await refusal { try await services.chat.askToSend() }
        let studio = await refusal { try await services.imageStudio.askToSend() }
        XCTAssertEqual([voice, chat, studio], [.notNow, .notNow, .notNow])
        XCTAssertEqual(sheets, 3, "each start asks while not granted")
        XCTAssertEqual(consent.sentRequests, 0, "asking sends nothing")
        let plain = await refusal { try await MockVoiceTranscriptionService().askToSend() }
        XCTAssertNil(plain)
    }

    func testTheCancelledLinePointsToSettings() {
        XCTAssertEqual(AIConsentError.notNow.errorDescription,
                       "Mira needs your OK to use AI. You can turn it on in Settings.")
    }

    func testLiveStudioReportsWhatRunsOnThePhone() {
        let live = ServiceContainer.live.imageStudio as? LiveImageStudioService
        XCTAssertEqual(live?.cutsLocally, true)
        XCTAssertEqual(live?.outlinesLocally, true)
        XCTAssertEqual(LiveImageStudioService().cutsLocally, false)
        XCTAssertEqual(LiveImageStudioService().outlinesLocally, false)
    }
}

private actor CountingTextTransform: TextTransformService {
    private(set) var calls = 0

    func transform(_ text: String, mode: TextTransformMode) async throws -> String {
        calls += 1
        return text
    }
}

private extension ServiceContainer {
    func replacingText(_ text: TextTransformService) -> ServiceContainer {
        ServiceContainer(textTransform: text, voiceTranscription: voiceTranscription,
                         stickerGeneration: stickerGeneration, styleTransfer: styleTransfer,
                         chat: chat, imageStudio: imageStudio, mood: mood)
    }
}
