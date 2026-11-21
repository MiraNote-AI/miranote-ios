import XCTest
@testable import MiraNoteKit

/// The paywall at a used-up allowance (api #95 step 4), and a Plus the
/// server has not heard of tried once more first.
@MainActor
final class AILimitPaywallTests: XCTestCase {
    private final class LimitedText: TextTransformService {
        let limit: AILimit
        init(_ limit: AILimit) { self.limit = limit }
        func transform(_ text: String, mode: TextTransformMode) async throws -> String {
            throw BackendError.limitReached(limit)
        }
        func rewrite(_ text: String, instruction: String) async throws -> String {
            throw BackendError.limitReached(limit)
        }
    }

    private func consent() -> AIConsent {
        AIConsent(defaults: UserDefaults(suiteName: "limit-test-\(UUID().uuidString)")!, grantedByDefault: true)
    }

    func testAFreeLimitOnAnActionShowsThePaywall() async {
        let consent = consent()
        var shown: [AILimit] = []
        consent.limitReached = { shown.append($0) }
        let free = AILimit(feature: "expand", plan: "free")
        let services = ServiceContainer(
            textTransform: LimitedText(free), voiceTranscription: MockVoiceTranscriptionService(),
            stickerGeneration: MockStickerGenerationService(), styleTransfer: MockStyleTransferService()
        ).asking(consent)
        do {
            _ = try await services.textTransform.transform("tea", mode: .expand)
            XCTFail("expected the limit")
        } catch {
            XCTAssertEqual(error as? BackendError, .limitReached(free), "the action still fails")
        }
        XCTAssertEqual(shown, [free])
    }

    func testAPlusLimitDoesNotOfferPlus() async {
        let consent = consent()
        var shown = 0
        consent.limitReached = { _ in shown += 1 }
        let services = ServiceContainer(
            textTransform: LimitedText(AILimit(feature: "expand", plan: "plus")),
            voiceTranscription: MockVoiceTranscriptionService(),
            stickerGeneration: MockStickerGenerationService(), styleTransfer: MockStyleTransferService()
        ).asking(consent)
        _ = try? await services.textTransform.transform("tea", mode: .expand)
        XCTAssertEqual(shown, 0)
    }

    // MARK: Plus the server has not heard of

    /// The free limit until the server is told about Plus; counts tries.
    private final class FreeUntilSynced: TextTransformService, @unchecked Sendable {
        var synced = false
        var tries = 0
        func transform(_ text: String, mode: TextTransformMode) async throws -> String {
            tries += 1
            guard synced else { throw BackendError.limitReached(AILimit(feature: "expand", plan: "free")) }
            return "expanded"
        }
        func rewrite(_ text: String, instruction: String) async throws -> String {
            try await transform(text, mode: .expand)
        }
    }

    private func services(_ text: TextTransformService, _ consent: AIConsent) -> ServiceContainer {
        ServiceContainer(
            textTransform: text, voiceTranscription: MockVoiceTranscriptionService(),
            stickerGeneration: MockStickerGenerationService(), styleTransfer: MockStyleTransferService()
        ).asking(consent)
    }

    /// A sync lost offline after a purchase: the phone has Plus, the
    /// server answers the free limit. The server is told, and the action
    /// tried once more instead of opening the paywall.
    func testAFreeLimitWithPlusOnThePhoneSyncsAndTriesOnceMore() async throws {
        let consent = consent()
        let text = FreeUntilSynced()
        var shown = 0
        consent.limitReached = { _ in shown += 1 }
        consent.syncPlus = {
            text.synced = true
            return true
        }
        let result = try await services(text, consent).textTransform.transform("tea", mode: .expand)
        XCTAssertEqual(result, "expanded")
        XCTAssertEqual(text.tries, 2)
        XCTAssertEqual(shown, 0)
    }

    func testAFreeLimitAfterTheSyncShowsThePaywallWithoutAThirdTry() async {
        let consent = consent()
        let text = FreeUntilSynced()
        var syncs = 0
        var shown = 0
        consent.limitReached = { _ in shown += 1 }
        consent.syncPlus = {
            syncs += 1
            return true
        }
        _ = try? await services(text, consent).textTransform.transform("tea", mode: .expand)
        XCTAssertEqual(syncs, 1)
        XCTAssertEqual(text.tries, 2)
        XCTAssertEqual(shown, 1)
    }

    /// No Plus on the phone, or the sync failed: the paywall at once.
    func testAFreeLimitWithoutPlusOnThePhoneDoesNotTryAgain() async {
        let consent = consent()
        let text = FreeUntilSynced()
        var shown = 0
        consent.limitReached = { _ in shown += 1 }
        consent.syncPlus = { false }
        _ = try? await services(text, consent).textTransform.transform("tea", mode: .expand)
        XCTAssertEqual(text.tries, 1)
        XCTAssertEqual(shown, 1)
    }
}
