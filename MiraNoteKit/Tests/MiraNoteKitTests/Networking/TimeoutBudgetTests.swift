import XCTest
@testable import MiraNoteKit

/// The client must give up before Cloudflare does, so a tester never sees a
/// raw edge error. Cloudflare's proxy read timeout is 125s and cannot be
/// raised below the Enterprise plan, which makes it a ceiling rather than a
/// tuning knob.
final class TimeoutBudgetTests: XCTestCase {
    /// Cloudflare's proxy read timeout. Not ours to change.
    private let edgeCeiling: TimeInterval = 125

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func capturedTimeout(_ run: () async throws -> Void) async -> TimeInterval? {
        var captured: TimeInterval?
        StubURLProtocol.handler = { request in
            captured = request.timeoutInterval
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"images":[],"raw_text":"x","corrected_text":"x"}"#.utf8))
        }
        try? await run()
        return captured
    }

    func testImageGenerationGivesUpBeforeTheEdgeDoes() async throws {
        let studio = LiveImageStudioService(
            baseURL: URL(string: "http://localhost:8002")!,
            client: HTTPClient(session: StubURLProtocol.makeSession())
        )
        let timeout = await capturedTimeout {
            _ = try await studio.generate(kind: GeneratedImageKind.sticker, prompt: "a cat")
        }
        let value = try XCTUnwrap(timeout)
        XCTAssertLessThan(value, edgeCeiling, "a request that outlives the edge can only ever 524")
        XCTAssertEqual(value, 110)
    }

    func testVoiceTranscriptionSetsAnExplicitBudget() async throws {
        let service = LiveVoiceTranscriptionService(
            baseURL: URL(string: "http://localhost:8005")!,
            client: HTTPClient(session: StubURLProtocol.makeSession()),
            language: "en"
        )
        let timeout = await capturedTimeout {
            _ = try await service.transcribe(audio: Data("A".utf8), filename: "r.m4a")
        }
        let value = try XCTUnwrap(timeout)
        // URLSession's implicit 60s already fails a one-minute recording: the
        // backend was measured at a worst case of 84.3s.
        XCTAssertGreaterThan(value, 84.3, "the measured worst case would not fit")
        XCTAssertLessThan(value, edgeCeiling)
        XCTAssertEqual(value, 110)
    }

    /// The coordinator's budget has to outlast the request it wraps, or its
    /// generic message fires first and the real transport error is lost. This
    /// was inverted before: request 180s against a coordinator 150s.
    @MainActor
    func testTheCoordinatorOutlastsTheRequestItWraps() {
        let coordinator = MiraCanvasCoordinator(text: ScriptedText(), chat: ScriptedChat())
        let coordinatorBudget = coordinator.imageTimeout
        XCTAssertEqual(coordinatorBudget, .seconds(120))
        XCTAssertGreaterThan(
            coordinatorBudget, .seconds(110),
            "the coordinator must not fire before the request it is waiting on"
        )
        XCTAssertLessThan(
            coordinatorBudget, .seconds(Int(edgeCeiling)),
            "no budget may sit above the edge ceiling"
        )
    }
}
