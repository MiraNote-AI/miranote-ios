import CoreGraphics
import XCTest
@testable import MiraNoteKit

final class MoodJudgeTests: XCTestCase {
    private func text(_ words: String, y top: CGFloat) -> CanvasItem {
        CanvasItem(content: .text(TextBlock(text: words)), position: CGPoint(x: 180, y: top))
    }

    @MainActor
    func testJudgeAsksOneAtATimeAndWritesEachAnswer() async {
        let service = CountingMoodService(answer: .tender)
        let pages = (0..<4).map { Memory(title: "Page \($0)") }
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: pages)])
        let judge = MoodJudge(service: service, library: viewModel)

        judge.judge(pages.map(\.id))
        judge.judge(pages.map(\.id))
        await waitUntil { pages.allSatisfy { viewModel.memory($0.id)?.mood == .tender } }

        let counts = await service.counts()
        XCTAssertEqual(counts.calls, 4, "a page already waiting is not asked twice")
        XCTAssertEqual(counts.mostAtOnce, 1, "at most one request at a time")
    }

    @MainActor
    func testNothingToReadIsNeutralWithoutAsking() async {
        let service = CountingMoodService(answer: .joyful)
        let stickers = Memory(items: [
            CanvasItem(content: .sticker(GeneratedSticker(prompt: "cat", symbolName: "sparkles")), position: .zero)
        ])
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [stickers])])
        MoodJudge(service: service, library: viewModel).judge([stickers.id])
        await waitUntil { viewModel.memory(stickers.id)?.mood != nil }

        XCTAssertEqual(viewModel.memory(stickers.id)?.mood, .neutral)
        let counts = await service.counts()
        XCTAssertEqual(counts.calls, 0)
    }

    @MainActor
    func testAFailedAskLeavesTheMoodUnjudged() async {
        let service = CountingMoodService(answer: nil)
        let page = Memory(title: "Offline day")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        MoodJudge(service: service, library: viewModel).judge([page.id])
        await waitUntil { await service.counts().calls == 1 }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(viewModel.memory(page.id)?.mood, "left unjudged")
    }

    @MainActor
    func testAFailedAskIsNotRepeatedUntilItsRetryTime() async {
        let service = CountingMoodService(answer: nil)
        let page = Memory(title: "Offline day")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        let judge = MoodJudge(service: service, library: viewModel)
        judge.show([page.id])
        await waitUntil { await service.counts().calls == 1 }
        judge.show([page.id])
        judge.judge([page.id])
        try? await Task.sleep(for: .milliseconds(100))
        let calls = await service.counts().calls
        XCTAssertEqual(calls, 1, "the jar shown again asks no more while offline")

        let soon = MoodJudge(service: service, library: viewModel, retryAfter: 0)
        soon.show([page.id])
        await waitUntil { await service.counts().calls == 2 }
    }

    @MainActor
    func testAPageJudgedFromTheSameWordsIsNotAskedAgain() async {
        let service = CountingMoodService(answer: .calm)
        let page = Memory(title: "A quiet walk")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        let judge = MoodJudge(service: service, library: viewModel)
        judge.judge([page.id])
        // Shown while its ask is in flight: queued, but not asked twice.
        judge.show([page.id])
        await waitUntil { viewModel.memory(page.id)?.mood == .calm }
        // Opened and closed without a change: filed and judged again.
        viewModel.file(page, underCollectionTitled: "Daily Log")
        judge.judge([page.id])
        try? await Task.sleep(for: .milliseconds(100))

        let calls = await service.counts().calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(viewModel.memory(page.id)?.moodTextHash, Memory.moodHash(of: page.moodText))
    }

    @MainActor
    func testAJarLeftIsNotAskedFor() async {
        let service = CountingMoodService(answer: .calm)
        let pages = (0..<4).map { Memory(title: "Page \($0)") }
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: pages)])
        let judge = MoodJudge(service: service, library: viewModel)
        judge.show(pages.map(\.id))
        await waitUntil { await service.counts().calls == 1 }
        judge.show([])
        await waitUntil { viewModel.memory(pages[0].id)?.mood == .calm }
        try? await Task.sleep(for: .milliseconds(100))

        let calls = await service.counts().calls
        XCTAssertEqual(calls, 1, "only the ask already in flight")
    }

    /// The editor's copy carries the mood it opened with; filing it never
    /// puts that back over a newer answer.
    @MainActor
    func testFilingAnEditorsCopyKeepsTheShelvesMood() {
        let page = Memory(title: "Lunch")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        let opened = viewModel.memory(page.id)!
        viewModel.setMood(.joyful, judgedFrom: "h", for: page.id)
        viewModel.file(opened, underCollectionTitled: "Daily Log")

        XCTAssertEqual(viewModel.memory(page.id)?.mood, .joyful)
        XCTAssertEqual(viewModel.memory(page.id)?.moodTextHash, "h")
    }

    /// An edit saved while the page's mood is on its way: the answer lands
    /// on the edited page, which -- its words changed -- is asked again,
    /// and ends with the mood of its new words.
    @MainActor
    func testAnEditSavedWhileTheMoodIsOnItsWayIsJudgedAgain() async {
        let service = CountingMoodService(answer: nil, byWord: ["picnic": .joyful, "rain": .low])
        let page = Memory(title: "A picnic")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        let judge = MoodJudge(service: service, library: viewModel)
        let opened = viewModel.memory(page.id)!

        judge.judge([page.id])
        await waitUntil { await service.counts().calls == 1 }
        var edited = opened
        edited.items = [text("rain all day", y: 100)]
        viewModel.file(edited, underCollectionTitled: "Daily Log")
        judge.judge([page.id])
        await waitUntil { viewModel.memory(page.id)?.mood == .low }

        let stored = viewModel.memory(page.id)
        XCTAssertEqual(stored?.items, edited.items, "the edit is kept")
        XCTAssertEqual(stored?.moodTextHash, Memory.moodHash(of: edited.moodText))
        let asked = await service.asked()
        XCTAssertEqual(asked, [page.moodText, edited.moodText])
    }

    /// Judged from older words, and the ask at the Save that changed them
    /// failed: the jar offers every shown page, and the judge asks only
    /// this one again.
    @MainActor
    func testAJudgedPageWhoseWordsChangedIsAskedAgainWhenShown() async {
        let service = CountingMoodService(answer: .low)
        let page = Memory(title: "A picnic")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        viewModel.setMood(.joyful, judgedFrom: Memory.moodHash(of: page.moodText), for: page.id)
        var edited = viewModel.memory(page.id)!
        edited.items = [text("rain all day", y: 100)]
        viewModel.file(edited, underCollectionTitled: "Daily Log")
        let judge = MoodJudge(service: service, library: viewModel)

        // What the jar used to offer: only the pages with no mood.
        judge.show(viewModel.collections.flatMap(\.memories).filter { $0.mood == nil }.map(\.id))
        try? await Task.sleep(for: .milliseconds(100))
        let before = await service.counts().calls
        XCTAssertEqual(before, 0)

        judge.show([page.id])
        await waitUntil { viewModel.memory(page.id)?.mood == .low }
        let after = await service.counts().calls
        XCTAssertEqual(after, 1)
        XCTAssertEqual(viewModel.memory(page.id)?.moodTextHash, Memory.moodHash(of: edited.moodText))
    }

    /// A draft's words are not the page's (#137): a page never saved has
    /// no mood to ask, and a saved page left as a draft keeps the mood its
    /// last Save got, whether Save or the jar queued it. The next Save asks.
    @MainActor
    func testADraftIsNotAsked() async {
        let service = CountingMoodService(answer: .low)
        let unsaved = Memory(items: [text("half a thought", y: 100)], isDraft: true)
        let page = Memory(items: [text("A picnic", y: 100)])
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [unsaved, page])])
        viewModel.setMood(.joyful, judgedFrom: Memory.moodHash(of: page.moodText), for: page.id)
        var draft = viewModel.memory(page.id)!
        draft.items = [text("rain all day", y: 100)]
        draft.isDraft = true
        viewModel.file(draft, underCollectionTitled: "Daily Log")
        let judge = MoodJudge(service: service, library: viewModel)

        judge.judge([unsaved.id, page.id])
        judge.show([unsaved.id, page.id])
        try? await Task.sleep(for: .milliseconds(100))
        let calls = await service.counts().calls
        XCTAssertEqual(calls, 0, "no draft's words are asked")
        XCTAssertNil(viewModel.memory(unsaved.id)?.mood)
        XCTAssertEqual(viewModel.memory(page.id)?.mood, .joyful, "the last Save's mood stays")

        var saved = viewModel.memory(page.id)!
        saved.isDraft = false
        viewModel.file(saved, underCollectionTitled: "Daily Log")
        judge.judge([page.id])
        await waitUntil { viewModel.memory(page.id)?.mood == .low }
    }

    /// The page as it is at its turn, not as it was queued: Save queued
    /// it, and Home left it a draft before the turn came.
    @MainActor
    func testAPageThatBecameADraftWhileQueuedIsNotAsked() async {
        let service = CountingMoodService(answer: .low)
        let page = Memory(items: [text("A picnic", y: 100)])
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        let judge = MoodJudge(service: service, library: viewModel)

        judge.judge([page.id])
        var draft = viewModel.memory(page.id)!
        draft.items = [text("rain all day", y: 100)]
        draft.isDraft = true
        viewModel.file(draft, underCollectionTitled: "Daily Log")
        try? await Task.sleep(for: .milliseconds(100))

        let calls = await service.counts().calls
        XCTAssertEqual(calls, 0, "its turn finds a draft")
        XCTAssertNil(viewModel.memory(page.id)?.mood)
    }

    /// Offline, no access, no endpoint, rate-limited, tunnel down: the
    /// first failure pauses the queue, not one request per page.
    @MainActor
    func testAnErrorAboutTheServicePausesTheWholeQueue() async {
        for error in [BackendError.unreachable, .timedOut, .server(status: 401, detail: nil),
                      .server(status: 404, detail: nil), .server(status: 429, detail: nil),
                      .server(status: 530, detail: nil)] {
            let service = CountingMoodService(answer: nil, error: error)
            let pages = (0..<3).map { Memory(title: "Page \($0)") }
            let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: pages)])
            let judge = MoodJudge(service: service, library: viewModel, gap: .zero)
            judge.show(pages.map(\.id))
            judge.judge([pages[2].id])
            await waitUntil { await service.counts().calls == 1 }
            try? await Task.sleep(for: .milliseconds(100))
            judge.show(pages.map(\.id))
            try? await Task.sleep(for: .milliseconds(50))

            let calls = await service.counts().calls
            XCTAssertEqual(calls, 1, "\(error): paused after the first failure")
        }
    }

    @MainActor
    func testAPausedQueueAsksAgainOnceTheRetryTimeHasPassed() async {
        let service = CountingMoodService(answer: nil, error: .server(status: 530, detail: nil))
        let pages = (0..<2).map { Memory(title: "Page \($0)") }
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: pages)])
        let judge = MoodJudge(service: service, library: viewModel, retryAfter: 0.2, gap: .zero)
        judge.show(pages.map(\.id))
        await waitUntil { await service.counts().calls == 1 }
        try? await Task.sleep(for: .milliseconds(300))
        judge.show(pages.map(\.id))
        await waitUntil { await service.counts().calls == 2 }
    }

    /// The server's 502 (it could not read the model's reply) is about the
    /// page: the others are still asked, and the page is not stored as
    /// neutral but asked again after `retryAfter`.
    @MainActor
    func testAnUnreadableReplyFailsOnlyThatPage() async {
        let service = CountingMoodService(answer: nil, error: .server(status: 502, detail: nil))
        let pages = (0..<3).map { Memory(title: "Page \($0)") }
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: pages)])
        let judge = MoodJudge(service: service, library: viewModel, gap: .zero)
        judge.show(pages.map(\.id))
        await waitUntil { await service.counts().calls == 3 }
        judge.show(pages.map(\.id))
        try? await Task.sleep(for: .milliseconds(100))

        let calls = await service.counts().calls
        XCTAssertEqual(calls, 3, "each page waits out its own retry time")
        XCTAssertTrue(pages.allSatisfy { viewModel.memory($0.id)?.mood == nil }, "not stored as neutral")
    }

    @MainActor
    func testConsecutiveAsksAreSpacedByTheGap() async {
        let service = CountingMoodService(answer: .calm)
        let pages = (0..<3).map { Memory(title: "Page \($0)") }
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: pages)])
        let judge = MoodJudge(service: service, library: viewModel, gap: .milliseconds(250))
        let start = ContinuousClock.now
        judge.judge(pages.map(\.id))
        await waitUntil { pages.allSatisfy { viewModel.memory($0.id)?.mood == .calm } }

        XCTAssertGreaterThanOrEqual(ContinuousClock.now - start, .milliseconds(500), "two gaps between three asks")
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out")
    }
}

/// Answers every ask with the mood of the first word in `byWord` the text
/// contains, else `answer` (nil: fails with `error`), after a beat,
/// counting the asks and how many were in flight at once.
private actor CountingMoodService: MoodService {
    let answer: Mood?
    let byWord: [String: Mood]
    let error: BackendError
    private var texts: [String] = []
    private var inFlight = 0
    private var mostAtOnce = 0

    init(answer: Mood?, byWord: [String: Mood] = [:], error: BackendError = .unreachable) {
        self.answer = answer
        self.byWord = byWord
        self.error = error
    }

    func counts() -> (calls: Int, mostAtOnce: Int) { (texts.count, mostAtOnce) }

    func asked() -> [String] { texts }

    func mood(for text: String) async throws -> Mood {
        texts.append(text)
        inFlight += 1
        mostAtOnce = max(mostAtOnce, inFlight)
        try? await Task.sleep(for: .milliseconds(20))
        inFlight -= 1
        let lowered = text.lowercased()
        if let match = byWord.first(where: { lowered.contains($0.key) }) { return match.value }
        guard let answer else { throw error }
        return answer
    }
}
