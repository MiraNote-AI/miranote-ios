import XCTest
@testable import MiraNoteKit

// MARK: - Tests

final class TriggerRunTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_761_926_400)   // 2026-10-31 16:00 UTC
    private var folder: URL!
    private var library: FakeLibrary!
    private var analyzer: FakeAnalyzer!
    private var notifier: FakeNotifier!
    private var client: FakeClient!
    private var sleeps: SleepLog!
    private var fake = false

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        library = FakeLibrary(now: now)
        analyzer = FakeAnalyzer()
        notifier = FakeNotifier()
        client = FakeClient()
        sleeps = SleepLog()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var records: PushRecordStore { PushRecordStore(directory: folder.appendingPathComponent("pushes")) }

    private func makeRun() -> TriggerRun {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = self.now
        let sleeps = self.sleeps!
        let fake = self.fake
        return TriggerRun(TriggerDependencies(
            library: library, analyzer: analyzer, places: NoPlaces(), client: client, notifier: notifier,
            analyses: AnalysisStore(directory: folder.appendingPathComponent("analysis")), records: records,
            calendar: calendar, now: { now }, sleep: { sleeps.record($0) }, fakeAI: { fake },
            zh: { "[\($0)]" }
        ))
    }

    /// The date (belongs-to day) of each group, rank 1 first.
    private func day(ofGroup group: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let first = library.assetsList.first { $0.id == "g\(group)-0" }!.takenAt!
        return FragmentGrouper.belongsTo(first, calendar: calendar)
    }

    private func scheduledRanks(_ history: [TriggerProgress]) -> [Int] {
        history.compactMap { if case .scheduled(let rank, _) = $0 { return rank } else { return nil } }
    }

    func testPushTopStartsAtRankOne() async {
        let run = makeRun()
        await run.pushTop()
        await run.pushTop()
        let history = await run.history
        XCTAssertEqual(scheduledRanks(history), [1, 1])
        XCTAssertEqual(client.submitted, [day(ofGroup: 0), day(ofGroup: 0)])
    }

    func testPushNextAdvancesFromLastSuccess() async {
        let run = makeRun()
        await run.pushTop()
        await run.pushNext()
        await run.pushNext()
        let runHistory = await run.history
        XCTAssertEqual(scheduledRanks(runHistory), [1, 2, 3])
    }

    func testPushNextWrapsWithNotice() async {
        library = FakeLibrary(now: now, groups: [10, 8])
        let run = makeRun()
        await run.pushNext()
        await run.pushNext()
        await run.pushNext()
        let history = await run.history
        XCTAssertEqual(scheduledRanks(history), [1, 2, 1])
        XCTAssertEqual(history.filter { $0 == .wrapped }.count, 1)
    }

    func testTriesAtMostThreeGroups() async {
        for group in 0..<5 { client.scripts[day(ofGroup: group)] = [.running, .rejected] }
        let run = makeRun()
        await run.pushTop()
        let history = await run.history
        XCTAssertEqual(client.submitted.count, 3)
        XCTAssertEqual(history.last, .allThreeFailed)
        XCTAssertEqual(history.filter { if case .rejected = $0 { return true } else { return false } },
                       [.rejected(rank: 1, message: "no \(day(ofGroup: 0))", next: 2),
                        .rejected(rank: 2, message: "no \(day(ofGroup: 1))", next: 3)])
    }

    func testAfterThreeFailuresNextContinuesAfterLastTried() async {
        for group in 0..<3 { client.scripts[day(ofGroup: group)] = [.rejected] }
        let run = makeRun()
        await run.pushTop()
        await run.pushNext()
        let runHistory = await run.history
        XCTAssertEqual(scheduledRanks(runHistory), [4])
        XCTAssertEqual(client.submitted.last, day(ofGroup: 3))
    }

    func testProgressOrder() async {
        let run = makeRun()
        await run.pushTop()
        let history = await run.history
        XCTAssertEqual(history.first, .preparing)
        XCTAssertEqual(history[1], .analyzing(done: 0, total: 33))
        XCTAssertEqual(history.filter { if case .analyzing = $0 { return true } else { return false } }.last,
                       .analyzing(done: 33, total: 33))
        guard case .askingAI(let rank, let date, let place, let count) = history[history.count - 2] else {
            return XCTFail("\(history)")
        }
        XCTAssertEqual(rank, 1)
        XCTAssertEqual(date, TriggerWords.shortDate(day(ofGroup: 0)))
        XCTAssertNil(place)
        XCTAssertEqual(count, 10)
        guard case .scheduled(1, let score) = history.last else { return XCTFail("\(history)") }
        XCTAssertGreaterThanOrEqual(score, 0.40)
    }

    /// A second launch analyses only photos it has not seen (B5).
    func testSecondRunAnalysesOnlyNewPhotos() async {
        await makeRun().pushTop()
        XCTAssertEqual(analyzer.analyzed.count, 33)
        library.assetsList.append(LibraryAsset(id: "new", takenAt: now.addingTimeInterval(-3 * 86_400), location: nil,
                                               isFavorite: false, isEdited: false, isScreenshot: false,
                                               isHidden: false, isVideo: false, originalFilename: nil, burstId: nil))
        let again = makeRun()
        await again.pushTop()
        XCTAssertEqual(analyzer.analyzed.count, 34)
        XCTAssertEqual(analyzer.analyzed.last, "new")
        let againHistory = await again.history
        XCTAssertEqual(againHistory[1], .analyzing(done: 33, total: 34))
    }

    func testExpiredJobResubmitsOnce() async {
        client.scripts[day(ofGroup: 0)] = [.running, .expired]
        let run = makeRun()
        await run.pushTop()
        // First job expires; the resubmitted job (same group) expires too.
        XCTAssertEqual(client.submitted, [day(ofGroup: 0), day(ofGroup: 0)])
        let runHistory = await run.history
        XCTAssertEqual(runHistory.last, .failed(.aiTimeout))
    }

    func testExpiredThenOkSchedules() async {
        final class Once: ComposeClient, @unchecked Sendable {
            let inner: FakeClient
            var expiredOnce = false
            init(_ inner: FakeClient) { self.inner = inner }
            func submit(_ meta: ComposeMeta, photos: [(id: String, jpeg: Data)]) async throws -> String {
                try await inner.submit(meta, photos: photos)
            }
            func poll(_ jobId: String) async throws -> ComposeJobStatus {
                if !expiredOnce { expiredOnce = true; return .expired }
                return try await inner.poll(jobId)
            }
        }
        let inner = client!
        let once = Once(inner)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = self.now
        let run = TriggerRun(TriggerDependencies(
            library: library, analyzer: analyzer, places: NoPlaces(), client: once, notifier: notifier,
            analyses: AnalysisStore(directory: folder.appendingPathComponent("analysis")), records: records,
            calendar: calendar, now: { now }, sleep: { _ in }, fakeAI: { false }, zh: { $0 }))
        await run.pushTop()
        XCTAssertEqual(inner.submitted.count, 2)
        let runHistory = await run.history
        XCTAssertEqual(scheduledRanks(runHistory), [1])
    }

    func testRateLimitedWaitsTenSeconds() async {
        client.scripts[day(ofGroup: 0)] = [.rateLimited, .running, .ok]
        let run = makeRun()
        await run.pushTop()
        XCTAssertEqual(sleeps.durations, [5, 10, 5, 5])
        let runHistory = await run.history
        XCTAssertEqual(scheduledRanks(runHistory), [1])
    }

    func testTimeoutAfterSixMinutes() async {
        client.scripts[day(ofGroup: 0)] = [.running]
        let run = makeRun()
        await run.pushTop()
        XCTAssertEqual(sleeps.durations.reduce(0, +), 360)
        XCTAssertEqual(sleeps.durations.count, 72, "every 5 s for 6 minutes")
        let runHistory = await run.history
        XCTAssertEqual(runHistory.last, .failed(.aiTimeout))
    }

    func testBackendTimeoutStopsAsAITimeout() async {
        client.scripts[day(ofGroup: 0)] = [.timeoutError]
        let run = makeRun()
        await run.pushTop()
        let runHistory = await run.history
        XCTAssertEqual(runHistory.last, .failed(.aiTimeout))
    }

    func testUnreachableBackendFails() async {
        client.submitErrors = [.unreachable]
        let run = makeRun()
        await run.pushTop()
        let runHistory = await run.history
        XCTAssertEqual(runHistory.last, .failed(.backendUnreachable))
    }

    func testNoFragmentFails() async {
        library.assetsList = []
        let run = makeRun()
        await run.pushTop()
        let runHistory = await run.history
        XCTAssertEqual(runHistory.last, .failed(.noFragment))
    }

    func testPermissionsFailEarly() async {
        notifier.allowed = false
        let off = makeRun()
        await off.pushTop()
        let offHistory = await off.history
        XCTAssertEqual(offHistory, [.preparing, .failed(.notificationsOff)])
        notifier.allowed = true
        library.access = .denied
        let denied = makeRun()
        await denied.pushTop()
        let deniedHistory = await denied.history
        XCTAssertEqual(deniedHistory, [.preparing, .failed(.photosDenied)])
        library.access = .limited
        let limited = makeRun()
        await limited.pushTop()
        let limitedHistory = await limited.history
        XCTAssertEqual(limitedHistory[1], .partialLibrary)
        XCTAssertEqual(scheduledRanks(limitedHistory), [1])
    }

}

/// The fake AI, records and press guards.
extension TriggerRunTests {
    func testFakeAIUsesB1AndF0() async throws {
        fake = true
        let run = makeRun()
        await run.pushTop()
        XCTAssertEqual(client.submitted, [], "the fake AI never calls the backend")
        let record = try XCTUnwrap(notifier.scheduled.first)
        let memory = record.memory
        XCTAssertEqual(memory.ending.questionId, "B1")
        XCTAssertEqual(memory.ending.detail, "")
        let body = "[\(TriggerContentKey.photosThatDay)]".replacingOccurrences(of: "%lld", with: "10")
        XCTAssertEqual(memory.push.body, body)
        XCTAssertEqual(memory.story.photos.count, 8, "ten preselected, the eight best")
        XCTAssertEqual(memory.story.photos.filter(\.isPeak).count, 1)
        XCTAssertEqual(memory.bucket, "[Food and drink]")
        XCTAssertEqual(record.photoIds.count, 10)
        XCTAssertEqual(memory.push.coverPhotoId, memory.peak?.id)
        XCTAssertEqual(records.load(record.pushId), record, "saved before it was scheduled")
    }

    func testDaypartConsistentAcrossTitleQuestionCta() async throws {
        fake = true
        let run = makeRun()
        await run.pushTop()
        let memory = try XCTUnwrap(notifier.scheduled.first?.memory)
        let peak = try XCTUnwrap(memory.peak)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let expected = Daypart(hour: calendar.component(.hour, from: peak.takenAt))
        XCTAssertEqual(memory.daypart, expected)
        let word = "[\(TriggerContentKey.daypart(expected))]"
        XCTAssertTrue(memory.push.title.hasSuffix(word), memory.push.title)
        XCTAssertTrue(memory.ending.question.contains(word))
        XCTAssertTrue(memory.ending.ctaLabel.contains(word))
        XCTAssertEqual(memory.ending.factLine, TriggerWords.shortDate(memory.date))
    }

    func testRecentQuestionIdsFromLastFiveRecords() throws {
        let store = records
        for index in 0..<7 {
            let base = TriggerMemoryTests.memory(ids: ["01", "02", "03"], peak: "01")
            let memory = TriggerMemory(
                id: "m\(index)", date: base.date, daypart: base.daypart, push: base.push, story: base.story,
                ending: .init(factLine: "f", detail: "", question: "q", questionId: "Q\(index)", ctaLabel: "c"))
            try store.save(PushRecord(pushId: UUID().uuidString, memory: memory, photoIds: [:],
                                      createdAt: now.addingTimeInterval(Double(index)), rank: 1, score: 0.5,
                                      bucket: ""))
        }
        XCTAssertEqual(store.recentQuestionIds(), ["Q6", "Q5", "Q4", "Q3", "Q2"])
    }

    func testPushIdIsNewEachTime() async {
        let run = makeRun()
        await run.pushTop()
        await run.pushTop()
        let ids = notifier.scheduled.map(\.pushId)
        XCTAssertEqual(ids.count, 2)
        XCTAssertNotEqual(ids[0], ids[1])
        XCTAssertEqual(records.all().count, 2)
    }

    func testSecondPressWhileRunningIsIgnored() async {
        client.scripts[day(ofGroup: 0)] = [.running, .running, .ok]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = self.now
        let run = TriggerRun(TriggerDependencies(
            library: library, analyzer: analyzer, places: NoPlaces(), client: client, notifier: notifier,
            analyses: AnalysisStore(directory: folder.appendingPathComponent("analysis")), records: records,
            calendar: calendar, now: { now }, sleep: { _ in try await Task.sleep(for: .milliseconds(30)) },
            fakeAI: { false }, zh: { $0 }))
        async let first: Void = run.pushTop()
        try? await Task.sleep(for: .milliseconds(20))
        await run.pushNext()
        await first
        XCTAssertEqual(client.submitted.count, 1)
        XCTAssertEqual(notifier.scheduled.count, 1)
    }
}
