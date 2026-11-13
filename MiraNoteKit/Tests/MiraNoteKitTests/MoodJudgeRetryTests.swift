import XCTest
@testable import MiraNoteKit

/// #159, after #192: which of the server's 502s are about the service,
/// tries that start over once nothing is left to ask, and a jar closed
/// while its page's ask is out.
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

    /// Tries an earlier outage spent are not carried over to a later Save.
    /// The jar was opened offline twice and left during each pause; later
    /// a page is saved and its first ask hits one hiccup. It is still
    /// asked again by itself, not stopped as a third failure in a row.
    @MainActor
    func testALaterSaveGetsFreshTriesAfterAnEarlierOutage() async {
        let service = ScriptedMoodService(failing: [1, 2, 3], error: .unreachable)
        let old = Memory(title: "Old page")
        let new = Memory(title: "New page")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [old, new])])
        let judge = MoodJudge(
            service: service, library: viewModel, gap: .zero,
            backoff: [.milliseconds(300), .milliseconds(300)]
        )

        for visit in 1...2 {
            judge.show([old.id])
            await waitUntil("jar visit \(visit) asked") { await service.calls == visit }
            try? await Task.sleep(for: .milliseconds(100))
            judge.show([])
            try? await Task.sleep(for: .milliseconds(400))
        }
        judge.judge([new.id])
        await waitUntil("the saved page asked again") { viewModel.memory(new.id)?.mood == .calm }
        let calls = await service.calls
        XCTAssertEqual(calls, 4, "two jar visits, the hiccup at Save, and the try that answered")
    }

    /// Also when the paused page needs no ask by its turn (Home left it a
    /// draft meanwhile): the next Save's hiccup is still asked again.
    @MainActor
    func testAPausedPageThatNeedsNoAskLeavesFreshTries() async {
        let service = ScriptedMoodService(failing: [1, 2], error: .unreachable)
        let first = Memory(title: "First page")
        let second = Memory(title: "Second page")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [first, second])])
        let judge = MoodJudge(service: service, library: viewModel, gap: .zero, backoff: [.milliseconds(200)])

        judge.judge([first.id])
        await waitUntil("the first page asked") { await service.calls == 1 }
        var draft = viewModel.memory(first.id)!
        draft.isDraft = true
        viewModel.file(draft, underCollectionTitled: "Daily Log")
        try? await Task.sleep(for: .milliseconds(400))

        judge.judge([second.id])
        await waitUntil("the second page asked again") { viewModel.memory(second.id)?.mood == .calm }
        let calls = await service.calls
        XCTAssertEqual(calls, 3, "the first page's failed try, the hiccup, and the try that answered")
    }

    /// The jar showed one page and closed while its ask was out; the ask
    /// hit a service error. A closed jar is not asked for.
    @MainActor
    func testAJarClosedWhileItsLastAskIsOutIsNotAskedForAgain() async {
        let service = ScriptedMoodService(failing: [1], error: .unreachable, beat: .milliseconds(200))
        let page = Memory(title: "Shown page")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        let judge = MoodJudge(service: service, library: viewModel, gap: .zero, backoff: [.milliseconds(50)])

        judge.show([page.id])
        await waitUntil("the ask went out") { await service.calls == 1 }
        judge.show([])
        try? await Task.sleep(for: .milliseconds(600))

        let calls = await service.calls
        XCTAssertEqual(calls, 1, "the closed jar's page is not asked again")
        XCTAssertNil(viewModel.memory(page.id)?.mood)
    }

    /// Shown again while the ask is out (the jar reopened): the page is
    /// still asked after the pause.
    @MainActor
    func testAJarShownAgainWhileTheAskIsOutStillGetsItsPageAsked() async {
        let service = ScriptedMoodService(failing: [1], error: .unreachable, beat: .milliseconds(200))
        let page = Memory(title: "Shown page")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        let judge = MoodJudge(service: service, library: viewModel, gap: .zero, backoff: [.milliseconds(50)])

        judge.show([page.id])
        await waitUntil("the ask went out") { await service.calls == 1 }
        judge.show([])
        judge.show([page.id])
        await waitUntil("asked again after the pause") { viewModel.memory(page.id)?.mood == .calm }

        let calls = await service.calls
        XCTAssertEqual(calls, 2)
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
