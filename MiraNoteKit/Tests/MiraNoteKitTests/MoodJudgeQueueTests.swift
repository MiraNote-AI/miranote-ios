import XCTest
@testable import MiraNoteKit

/// MoodJudge's queue as a whole, split from MoodJudgeTests.swift to keep
/// both under swiftlint's length limits: errors about the service pause
/// it and back off (#159), a page's own failure does not, asks are
/// spaced, and nothing is asked while moods are not allowed (#151).
extension MoodJudgeTests {
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

    /// #159: the ask at Save hit a service hiccup. With no further Save or
    /// jar visit the queue resumes by itself, asks the same page again, and
    /// the page's star -- already in the jar, uncolored -- takes the mood.
    @MainActor
    func testAPageWhoseAskHitAServiceErrorIsAskedAgainByItself() async {
        let service = CountingMoodService(answer: .calm, error: .server(status: 530, detail: nil), failFirst: 1)
        let page = Memory(title: "A quiet walk")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        let judge = MoodJudge(service: service, library: viewModel, gap: .zero, backoff: [.milliseconds(100)])
        let month = JarPeriod.month.interval(containing: page.memoryDate)

        judge.judge([page.id])
        await waitUntil { await service.counts().calls == 1 }
        XCTAssertEqual(StarJar.stars(in: viewModel.library, during: month).map(\.memory.mood), [nil])

        await waitUntil { viewModel.memory(page.id)?.mood == .calm }
        XCTAssertEqual(StarJar.stars(in: viewModel.library, during: month).map(\.memory.mood), [.calm])
        let calls = await service.counts().calls
        XCTAssertEqual(calls, 2)
    }

    /// Saved again and shown in the jar while paused: still one ask per
    /// try, not one per call.
    @MainActor
    func testAPausedPageQueuedAgainIsNotAskedTwice() async {
        let service = CountingMoodService(answer: .calm, error: .unreachable, failFirst: 1)
        let page = Memory(title: "A quiet walk")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        let judge = MoodJudge(service: service, library: viewModel, gap: .zero, backoff: [.milliseconds(150)])

        judge.judge([page.id])
        await waitUntil { await service.counts().calls == 1 }
        judge.judge([page.id])
        judge.show([page.id])
        await waitUntil { viewModel.memory(page.id)?.mood == .calm }
        try? await Task.sleep(for: .milliseconds(100))

        let calls = await service.counts().calls
        XCTAssertEqual(calls, 2, "the failed try and the one that answered")
    }

    /// Tries are bounded: after the last step of the backoff the queue
    /// waits, and coming back to the app (or the next Save) asks again.
    @MainActor
    func testTriesStopAfterTheBackoffAndResumeAsksAgain() async {
        let service = CountingMoodService(answer: nil, error: .server(status: 530, detail: nil))
        let page = Memory(title: "A quiet walk")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        let judge = MoodJudge(
            service: service, library: viewModel, gap: .zero,
            backoff: [.milliseconds(30), .milliseconds(30)]
        )

        judge.judge([page.id])
        await waitUntil { await service.counts().calls == 3 }
        try? await Task.sleep(for: .milliseconds(150))
        let spent = await service.counts().calls
        XCTAssertEqual(spent, 3, "one try and two retries")

        judge.resume()
        await waitUntil { await service.counts().calls == 4 }
    }

    /// #151 with #159: the mood switch turned off during a backoff pause --
    /// the wake-up asks nothing; turned on again, `resume()` asks.
    @MainActor
    func testABackoffWakeUpAsksNothingOnceMoodsAreOff() async {
        let service = CountingMoodService(answer: nil, error: .server(status: 530, detail: nil))
        let page = Memory(title: "A quiet walk")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        var allowed = true
        let judge = MoodJudge(
            service: service, library: viewModel, gap: .zero,
            backoff: [.milliseconds(50)], allowed: { allowed }
        )

        judge.judge([page.id])
        await waitUntil { await service.counts().calls == 1 }
        allowed = false
        try? await Task.sleep(for: .milliseconds(200))
        let paused = await service.counts().calls
        XCTAssertEqual(paused, 1, "off: the wake-up does not ask")

        allowed = true
        judge.resume()
        await waitUntil { await service.counts().calls == 2 }
    }

    /// The server's 502 (it could not read the model's reply) is about the
    /// page: the others are still asked, and the page is not stored as
    /// neutral but asked again after `retryAfter`.
    @MainActor
    func testAnUnreadableReplyFailsOnlyThatPage() async {
        let unreadable = BackendError.server(status: 502, detail: #"{"detail":"LLM reply named no mood"}"#)
        let service = CountingMoodService(answer: nil, error: unreadable)
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

    /// #151: no AI consent, or "Mood from my words" off -- nothing is
    /// asked; the queued page is asked once `resume()` finds it allowed.
    @MainActor
    func testNothingIsAskedWhileNotAllowedAndResumeAsksTheQueue() async {
        let service = CountingMoodService(answer: .calm)
        let page = Memory(title: "A quiet walk")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        var allowed = false
        let judge = MoodJudge(service: service, library: viewModel, allowed: { allowed })

        judge.judge([page.id])
        judge.show([page.id])
        try? await Task.sleep(for: .milliseconds(100))
        let before = await service.counts()
        XCTAssertEqual(before.calls, 0, "not allowed: no request")
        XCTAssertNil(viewModel.memory(page.id)?.mood)

        allowed = true
        judge.resume()
        await waitUntil { viewModel.memory(page.id)?.mood == .calm }
        let after = await service.counts()
        XCTAssertEqual(after.calls, 1)
    }
}
