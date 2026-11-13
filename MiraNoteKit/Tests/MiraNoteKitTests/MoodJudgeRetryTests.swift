import XCTest
@testable import MiraNoteKit

/// #159, after #192: which of the server's 502s are about the service.
final class MoodJudgeRetryTests: XCTestCase {
    /// miranote-api's /mood answers 502 "LLM call failed: ..." when its LLM
    /// provider fails (down, out of credit, out of reach), and a proxy in
    /// front of a stopped server answers 502 with its own page. Neither is
    /// about the page: it is asked again by itself and takes its mood.
    @MainActor
    func testA502FromTheProviderOrAProxyIsAskedAgainByItself() async {
        let details: [String?] = [
            #"{"detail":"LLM call failed: Connection error."}"#,
            #"{"detail":"LLM call failed after retries"}"#,
            "<html><body>502 Bad Gateway</body></html>",
            nil
        ]
        for detail in details {
            let service = ScriptedMoodService(failing: [1], error: .server(status: 502, detail: detail))
            let page = Memory(title: "A quiet walk")
            let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
            let judge = MoodJudge(service: service, library: viewModel, gap: .zero, backoff: [.milliseconds(50)])

            judge.judge([page.id])
            await waitUntil("\(detail ?? "no body"): asked again") { viewModel.memory(page.id)?.mood == .calm }
            let calls = await service.calls
            XCTAssertEqual(calls, 2, "\(detail ?? "no body"): the failed try and the one that answered")
        }
    }

    /// The server's own 502s about the model's reply stay about the page:
    /// the next page is asked at once, and this one waits out `retryAfter`
    /// with no mood rather than a guessed one.
    @MainActor
    func testA502AboutTheModelsReplyFailsOnlyThatPage() async {
        for detail in [#"{"detail":"LLM reply named no mood"}"#, #"{"detail":"LLM reply was empty or cut off"}"#] {
            let service = ScriptedMoodService(failing: [1], error: .server(status: 502, detail: detail))
            let pages = [Memory(title: "Unreadable"), Memory(title: "A quiet walk")]
            let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: pages)])
            let judge = MoodJudge(service: service, library: viewModel, gap: .zero, backoff: [.milliseconds(50)])

            judge.judge(pages.map(\.id))
            await waitUntil("\(detail): the next page answered") { viewModel.memory(pages[1].id)?.mood == .calm }
            try? await Task.sleep(for: .milliseconds(200))
            let calls = await service.calls
            XCTAssertEqual(calls, 2, "\(detail): not asked again before retryAfter")
            XCTAssertNil(viewModel.memory(pages[0].id)?.mood, "\(detail): no mood guessed")
        }
    }

    @MainActor
    private func waitUntil(_ what: String, _ condition: @MainActor () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out: \(what)")
    }
}

/// Fails the asks whose number (from 1) is in `failing` with `error` and
/// answers the others `.calm`, each after `beat`; counts the asks.
private actor ScriptedMoodService: MoodService {
    let failing: Set<Int>
    let error: BackendError
    let beat: Duration
    private(set) var calls = 0

    init(failing: Set<Int>, error: BackendError, beat: Duration = .milliseconds(20)) {
        self.failing = failing
        self.error = error
        self.beat = beat
    }

    func mood(for text: String) async throws -> Mood {
        calls += 1
        let number = calls
        try? await Task.sleep(for: beat)
        if failing.contains(number) { throw error }
        return .calm
    }
}
