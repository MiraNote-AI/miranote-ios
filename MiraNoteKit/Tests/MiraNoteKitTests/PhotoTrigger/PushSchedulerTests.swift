import XCTest
@testable import MiraNoteKit

/// The scheduler on a fake clock, client and notification center. Seven
/// food groups g0...g6 (9...3 photos, 3...9 days old): g0 ranks first.
/// 2025-10-31 is a Friday; it is 11:00 in Chicago.
class PushSchedulerTestCase: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_761_926_400)   // 2025-10-31 16:00 UTC
    var folder: URL!
    var library: FakeLibrary!
    var analyzer: FakeAnalyzer!
    var notifier: FakeNotifier!
    var client: FakeClient!
    var clock: TestClock!
    var sleeps: SleepLog!
    var hook: SleepHook!
    var zone: ZoneBox!
    var places: PlaceNaming = NoPlaces()
    var fake = false

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        library = FakeLibrary(now: start, groups: [9, 8, 7, 6, 5, 4, 3])
        analyzer = FakeAnalyzer()
        notifier = FakeNotifier()
        client = FakeClient()
        clock = TestClock(start)
        sleeps = SleepLog()
        hook = SleepHook()
        zone = ZoneBox(TimeZone(identifier: "America/Chicago")!)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    var ledger: PushLedgerStore { PushLedgerStore(file: folder.appendingPathComponent("ledger.json")) }
    var records: PushRecordStore { PushRecordStore(directory: folder.appendingPathComponent("pushes")) }
    var preferences: PushPreferencesStore {
        PushPreferencesStore(file: folder.appendingPathComponent("preferences.json"))
    }
    var cache: AIResultCache { AIResultCache(file: folder.appendingPathComponent("ai-cache.json")) }
    var log: ScheduleLogStore { ScheduleLogStore(file: folder.appendingPathComponent("schedule-log.json")) }
    var state: SchedulerStateStore { SchedulerStateStore(file: folder.appendingPathComponent("state.json")) }
    var lastRun: LastRunStore { LastRunStore(file: folder.appendingPathComponent("last-run.json")) }

    func makeScheduler() -> PushScheduler {
        let clock = self.clock!
        let sleeps = self.sleeps!
        let hook = self.hook!
        let zone = self.zone!
        let fake = self.fake
        return PushScheduler(SchedulerDependencies(
            library: library, analyzer: analyzer, places: places, client: client, notifications: notifier,
            analyses: AnalysisStore(directory: folder.appendingPathComponent("analysis")), records: records,
            ledger: ledger, preferences: preferences, cache: cache, log: log, state: state, lastRun: lastRun,
            calendar: { zone.calendar }, now: { clock.now },
            sleep: { seconds in
                if Task.isCancelled {
                    // Task.sleep throws at once and no time passes -- past
                    // 100 such sleeps the clock moves, so a loop that ignores
                    // the cancel still ends (and its test fails, not hangs).
                    if sleeps.recordCancelled() > 100 { clock.advance(seconds) }
                    throw CancellationError()
                }
                clock.advance(seconds)
                sleeps.record(seconds)
                await hook.fire()
            },
            fakeAI: { fake }, zh: { "[\($0)]" }))
    }

    /// The belongs-to day of group `prefix`.
    func day(_ prefix: String) -> String {
        let first = library.assetsList.first { $0.id == "\(prefix)-0" }!.takenAt!
        return FragmentGrouper.belongsTo(first, calendar: zone.calendar)
    }

    /// Active pushes in night order.
    var active: [LedgerEntry] {
        ledger.load().filter(\.isActive).sorted { $0.scheduledFor < $1.scheduledFor }
    }

    /// The belongs-to days of the active pushes, night by night.
    var activeDays: [String] { active.map(\.belongsTo) }

    func groups(_ prefixes: [String]) -> [String] { prefixes.map(day) }

    var allSeven: [String] { groups(["g0", "g1", "g2", "g3", "g4", "g5", "g6"]) }

    /// A larger, newer group: it ranks first.
    func addBest(_ prefix: String = "n", daysAgo: Double = 2) {
        library.add(prefix, start: start.addingTimeInterval(-daysAgo * 86_400 - 6 * 3600), count: 12)
    }
}

// MARK: - The run

final class PushSchedulerTests: PushSchedulerTestCase {
    func testReplacedOnlyWhenNewPasses() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        addBest()
        client.scripts[day("n")] = [.rejected]
        clock.advance(3600)
        await scheduler.appBecameActive()
        XCTAssertEqual(active.first, tonight, "turned down: tonight's push stays")
        XCTAssertFalse(ledger.load().contains { $0.removedReason == .replaced })

        addBest("m", daysAgo: 1)
        clock.advance(3600)
        await scheduler.appBecameActive()
        XCTAssertEqual(active.first?.belongsTo, day("m"), "passed: it takes tonight")
        let replaced = try XCTUnwrap(ledger.load().first { $0.pushId == tonight.pushId })
        XCTAssertEqual(replaced.removedReason, .replaced)
        XCTAssertTrue(notifier.removedPending.contains(tonight.identifier))
        XCTAssertEqual(Set(activeDays).count, activeDays.count, "a belongs-to day is planned once")
        XCTAssertEqual(activeDays.count, 7)
    }

    func testNoReplacementWithinAnHour() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        addBest()
        clock.now = tonight.scheduledFor.addingTimeInterval(-45 * 60)
        await scheduler.appBecameActive()
        XCTAssertEqual(active.first, tonight, "45 min before it fires: kept")
        XCTAssertEqual(active.dropFirst().first?.belongsTo, day("n"), "the new group takes tomorrow")
    }

    func testWithinAnHourSkipsFullRun() async {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        clock.advance(30 * 60)
        await scheduler.appBecameActive()
        XCTAssertEqual(log.runs().count, 1)
        clock.advance(31 * 60)
        await scheduler.appBecameActive()
        XCTAssertEqual(log.runs().count, 2)
    }

    func testUnfilledDayRerunsAtOnce() async {
        client.scripts[day("g0")] = [.timeoutError]
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        client.scripts[day("g0")] = [.ok]
        clock.advance(5 * 60)
        await scheduler.appBecameActive()
        XCTAssertEqual(log.runs().count, 2, "the empty night is tried again at once")
        XCTAssertEqual(activeDays, allSeven)
        XCTAssertFalse(state.load().lastRunLeftDaysUnfilled)
    }

    func testTimeZoneChangeReplansAll() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let before = active
        zone.zone = TimeZone(identifier: "America/New_York")!
        clock.advance(10 * 60)
        await scheduler.appBecameActive()
        let entries = ledger.load()
        for entry in before {
            XCTAssertEqual(entries.first { $0.pushId == entry.pushId }?.removedReason, .timeZone)
        }
        XCTAssertEqual(log.runs().first?.trigger, "timeZone")
        XCTAssertEqual(active.count, 7)
        XCTAssertEqual(state.load().timeZoneId, "America/New_York")
        let last = try XCTUnwrap(notifier.scheduledAt.last ?? nil)
        XCTAssertEqual(last.hour, 21, "local time in the new zone")
    }

    func testOverlappingRunsCoalesce() async throws {
        for group in allSeven { client.scripts[group] = [.running, .ok] }
        let scheduler = makeScheduler()
        hook.action = { number in
            guard number == 1 else { return }
            await scheduler.replan()
            await scheduler.appBecameActive()
            await scheduler.replan()
        }
        await scheduler.replan()
        let running = await scheduler.isRunning
        XCTAssertFalse(running)
        XCTAssertEqual(log.runs().count, 2, "three requests while running: one rerun")
        XCTAssertEqual(client.submitted.count, 7, "the rerun reuses the cache: no second wave")
        XCTAssertEqual(active.count, 7)
    }

    func testRunWithNotificationsOffLogsErrorAndSchedulesNothing() async throws {
        notifier.allowed = false
        await makeScheduler().appBecameActive()
        XCTAssertTrue(notifier.scheduled.isEmpty)
        XCTAssertTrue(client.submitted.isEmpty)
        let run = try XCTUnwrap(log.runs().first)
        XCTAssertEqual(run.error, "notificationsOff")
        XCTAssertEqual(Set(run.emptyDays.values), ["notificationsOff"])
        XCTAssertEqual(run.emptyDays.count, 7)
    }

    /// Risk R10: a push iOS dropped while notifications were off leaves its
    /// day pushable; its group and day are free for the next allowed run.
    func testPushMissedWithNotificationsOffFreesItsGroupAndDay() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        XCTAssertEqual(tonight.belongsTo, day("g0"))
        notifier.allowed = false
        clock.now = tonight.scheduledFor.addingTimeInterval(3600)
        notifier.pendingIds.remove(tonight.identifier)
        await scheduler.appBecameActive()
        let dead = try XCTUnwrap(ledger.load().first { $0.pushId == tonight.pushId })
        XCTAssertEqual(dead.notDeliveredReason, "notificationsOff")
        XCTAssertFalse(dead.isActive)

        notifier.allowed = true
        let preview = await scheduler.previewNext()
        let tomorrow = PushSlots.make(now: clock.now, calendar: zone.calendar)[0]
        XCTAssertEqual(preview, .scheduled(slotDay: SchedulePlanner.day(tomorrow, calendar: zone.calendar)),
                       "the preview skips the dead push")
        XCTAssertNotEqual(notifier.scheduled.last?.belongsTo, day("g0"))

        clock.advance(10 * 60)
        await scheduler.appBecameActive()
        XCTAssertTrue(active.contains { $0.belongsTo == day("g0") && $0.pushId != tonight.pushId },
                      "the missed day is scheduled again")
        XCTAssertEqual(Set(activeDays).count, activeDays.count)
        XCTAssertEqual(activeDays.count, 7)
    }

    func testPhotosDeniedLogsError() async throws {
        library.access = .denied
        await makeScheduler().appBecameActive()
        XCTAssertTrue(notifier.scheduled.isEmpty)
        XCTAssertEqual(log.runs().first?.error, "photosDenied")
    }

    func testScheduledGroupWhosePhotosVanishedIsKeptUntilReplaced() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        library.remove("g0")
        clock.advance(3600)
        await scheduler.appBecameActive()
        XCTAssertEqual(active.first, tonight, "no group passed in its place: kept")
        XCTAssertEqual(active.count, 7)

        addBest()
        clock.advance(3600)
        await scheduler.appBecameActive()
        XCTAssertEqual(active.first?.belongsTo, day("n"))
        XCTAssertEqual(ledger.load().first { $0.pushId == tonight.pushId }?.removedReason, .replaced)
    }

    func testLedgerRowHasEveryField() async throws {
        places = FixedPlace()
        library = FakeLibrary(now: start, groups: [])
        library.add("g0", start: start.addingTimeInterval(-3 * 86_400 - 6 * 3600), count: 5,
                    location: GeoPoint(lat: 41.88, lon: -87.63))
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        var entry = try XCTUnwrap(active.first)
        XCTAssertEqual(entry.identifier, "pt." + entry.pushId)
        XCTAssertFalse(entry.isDebug)
        XCTAssertEqual(entry.belongsTo, day("g0"))
        XCTAssertTrue(entry.groupKey.hasPrefix(day("g0") + "_"))
        XCTAssertEqual(entry.photoIds, (0..<5).map { "g0-\($0)" })
        XCTAssertEqual(entry.bucket, .food)
        XCTAssertEqual(entry.place, "Riverside Park")
        XCTAssertGreaterThanOrEqual(entry.score.total, 0.40)
        XCTAssertEqual(entry.body, "b")
        XCTAssertEqual(entry.questionId, "B1")
        XCTAssertEqual(entry.scheduledFor, PushSlots.make(now: start, calendar: zone.calendar)[0])
        let record = try XCTUnwrap(records.load(entry.pushId))
        XCTAssertEqual(record.bucketId, .food)
        XCTAssertEqual(record.belongsTo, day("g0"))
        XCTAssertEqual(record.isDebug, false)

        clock.now = entry.scheduledFor.addingTimeInterval(60)
        notifier.pendingIds = []
        await scheduler.markOpened(entry.pushId)
        await scheduler.markStoryFinished(entry.pushId)
        await scheduler.markMadePage(entry.pushId)
        await scheduler.menu(.fewerLikeThis, pushId: entry.pushId)
        entry = try XCTUnwrap(ledger.load().first { $0.pushId == entry.pushId })
        XCTAssertEqual(entry.deliveredAt, entry.scheduledFor, "opened: it was delivered")
        XCTAssertNotNil(entry.openedAt)
        XCTAssertNotNil(entry.storyFinishedAt)
        XCTAssertNotNil(entry.madePageAt)
        XCTAssertEqual(entry.menuAction, .fewerLikeThis)
        XCTAssertNotNil(entry.menuActionAt)
        let data = try ledger.exportJSON()
        let text = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        XCTAssertFalse(text.contains("41.88"), "no coordinates in the ledger")
    }

    func testThresholdStableWithinAWeek() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let first = try XCTUnwrap(state.load().thresholdComputedAt)
        XCTAssertNotNil(state.load().threshold)
        clock.advance(2 * 3600)
        await scheduler.appBecameActive()
        XCTAssertEqual(state.load().thresholdComputedAt, first, "T kept within the week")
        clock.advance(7 * 86_400)
        await scheduler.appBecameActive()
        XCTAssertEqual(state.load().thresholdComputedAt, clock.now, "a week on: T computed again")
    }

    func testFakeAIIsUsedAndCached() async throws {
        fake = true
        await makeScheduler().appBecameActive()
        XCTAssertTrue(client.submitted.isEmpty)
        XCTAssertEqual(activeDays, allSeven)
        let key = AIResultCache.key((0..<9).map { "g0-\($0)" })
        guard case .ok(let memory, _) = cache.verdict(key) else { return XCTFail("cached like ok") }
        XCTAssertEqual(memory.ending.questionId, "B1")
    }

    func testStoresLoadEmptyFromGarbage() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["ledger.json", "preferences.json", "ai-cache.json", "schedule-log.json", "state.json",
                     "last-run.json"] {
            try Data("{garbage".utf8).write(to: folder.appendingPathComponent(name))
        }
        XCTAssertNil(lastRun.load())
        await makeScheduler().appBecameActive()
        XCTAssertEqual(activeDays, allSeven, "every store reads empty and the run goes on")
    }
}
