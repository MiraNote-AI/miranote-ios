import XCTest
@testable import MiraNoteKit

/// The chat box's Go while writing (#205 F6B): the block goes to the text
/// service's `/rewrite` with the writer's own words as the instruction
/// (miranote-api #126), and its failures reach the caption and the paywall
/// as Polish's do.
@MainActor
final class TextRewriteAskTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func live() -> LiveTextTransformService {
        LiveTextTransformService(
            baseURL: URL(string: "http://localhost:8001")!,
            client: HTTPClient(session: StubURLProtocol.makeSession())
        )
    }

    private func coordinator(_ text: TextTransformService) -> MiraCanvasCoordinator {
        MiraCanvasCoordinator(text: text, chat: ScriptedChat(), workingDelay: .milliseconds(1), timeout: .seconds(5))
    }

    private static func answer(_ request: URLRequest, _ status: Int, _ body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    func testGoSendsTheWordsAsTheInstruction() async throws {
        var sent: URLRequest?
        StubURLProtocol.handler = { request in
            sent = request
            return Self.answer(request, 200, #"{"original": "we walked", "rewritten": "We walked, warm."}"#)
        }
        let rewritten = try await coordinator(live()).rewriteText("we walked", asked: "make it warmer")

        XCTAssertEqual(rewritten, "We walked, warm.")
        XCTAssertEqual(sent?.httpMethod, "POST")
        XCTAssertEqual(sent?.url?.path, "/rewrite")
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent?.capturedBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["text"] as? String, "we walked")
        XCTAssertEqual(body["instruction"] as? String, "make it warmer")
        XCTAssertNil(body["context"], "no context is sent")
    }

    func testTheInstructionIsCappedAtTheServicesLimit() async throws {
        let rewritten = try await coordinator(ScriptedText())
            .rewriteText("we walked", asked: String(repeating: "a", count: 600))
        XCTAssertEqual(rewritten, "[\(String(repeating: "a", count: 500))] we walked")
    }

    /// A used-up free allowance opens the paywall and says the limit, as
    /// a Polish chip's does.
    func testAQuota429OpensThePaywall() async {
        StubURLProtocol.handler = { request in
            Self.answer(request, 429, #"{"reason": "quota", "feature": "expand", "plan": "free", "limit": 10,"#
                + #" "resets_at": "2026-12-01T00:00:00+00:00"}"#)
        }
        let consent = AIConsent(defaults: UserDefaults(suiteName: "rewrite-\(UUID().uuidString)")!,
                                grantedByDefault: true)
        var shown: [AILimit] = []
        consent.limitReached = { shown.append($0) }
        let services = ServiceContainer(
            textTransform: live(), voiceTranscription: MockVoiceTranscriptionService(),
            stickerGeneration: MockStickerGenerationService(), styleTransfer: MockStyleTransferService()
        ).asking(consent)

        do {
            _ = try await coordinator(services.textTransform).rewriteText("tea", asked: "make it warmer")
            XCTFail("expected the limit")
        } catch {
            let free = AILimit(feature: "expand", plan: "free")
            XCTAssertEqual(error as? BackendError, .limitReached(free))
            XCTAssertEqual(AIConsentError.message(for: error),
                           "You've reached the free limit for this. MiraNote Plus gives you more.")
            XCTAssertEqual(shown, [free], "the paywall opens")
        }
    }

    /// The model failing is an ordinary failure: the caption's retry line.
    func testAModelFailureIsAPlainFailure() async {
        StubURLProtocol.handler = { Self.answer($0, 502, #"{"detail": "model failed"}"#) }
        do {
            _ = try await coordinator(live()).rewriteText("tea", asked: "make it warmer")
            XCTFail("expected the failure")
        } catch {
            guard case .server(502, _) = error as? BackendError else { return XCTFail("got \(error)") }
            XCTAssertNil(AIConsentError.message(for: error), "the caption falls back to its retry line")
        }
    }
}
