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

    /// `fakeAI` switches mid-test when given; else `fake` as the scheduler is made.
    func makeScheduler(client other: ComposeClient? = nil, notifications: PushNotificationCenter? = nil,
                       fakeAI flag: FlagBox? = nil) -> PushScheduler {
        let clock = self.clock!
        let sleeps = self.sleeps!
        let hook = self.hook!
        let zone = self.zone!
        let fake = self.fake
        return PushScheduler(SchedulerDependencies(
            library: library, analyzer: analyzer, places: places, client: other ?? client,
            notifications: notifications ?? notifier,
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
            fakeAI: { flag?.value ?? fake }, zh: { "[\($0)]" }))
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
        XCTAssertEqual(entry.question, "q")
        XCTAssertEqual(entry.questionType, "one_word")
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

    func testFakeAIIsUsedNeverCached() async throws {
        fake = true
        await makeScheduler().appBecameActive()
        XCTAssertTrue(client.submitted.isEmpty)
        XCTAssertEqual(activeDays, allSeven)
        let memory = try XCTUnwrap(records.load(try XCTUnwrap(active.first).pushId)).memory
        XCTAssertTrue(memory.isFakeMade)
        XCTAssertEqual(memory.ending.questions.map(\.source), ["fallback_B1"])
        XCTAssertEqual(memory.ending.questionType, "one_word")
        XCTAssertTrue(cache.verdicts().isEmpty, "the fake AI's words never enter the cache")
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

// MARK: - The 60-day window

extension PushSchedulerTests {
    /// A5: every run asks the library again; nothing is cached between opens.
    func testEveryRunQueriesTheLibraryForTheLastSixtyDays() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        XCTAssertEqual(library.sinceDates.count, 1)
        clock.advance(2 * 3600)
        await scheduler.appBecameActive()
        let dates = library.sinceDates
        XCTAssertEqual(dates.count, 2, "two runs, two queries")
        XCTAssertLessThanOrEqual(dates[0], start.addingTimeInterval(-60 * 86_400))
        XCTAssertLessThanOrEqual(dates[1], clock.now.addingTimeInterval(-60 * 86_400))
        XCTAssertGreaterThan(dates[1], dates[0], "measured from each run's own now")
    }

    /// Place novelty looks back three months, not a year (decision 11-04).
    func testLibraryQueryReachesBackNinetyDaysForPlaces() async throws {
        await makeScheduler().appBecameActive()
        XCTAssertEqual(library.sinceDates, [start.addingTimeInterval(-90 * 86_400)])
    }
}

// MARK: - Take-backs never touch a push that already fired

/// A push whose time has passed was delivered (or dropped by iOS): a
/// take-back must leave it for the reconcile, or its day is pushed again.
final class PushSchedulerFiredPushTests: PushSchedulerTestCase {
    /// Tonight's push, fired `after` seconds ago and gone from the pending list.
    private func fireTonight(after seconds: TimeInterval) async throws -> (PushScheduler, LedgerEntry) {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        clock.now = tonight.scheduledFor.addingTimeInterval(seconds)
        notifier.pendingIds.remove(tonight.identifier)
        return (scheduler, tonight)
    }

    private func assertDelivered(_ fired: LedgerEntry, file: StaticString = #filePath, line: UInt = #line) throws {
        let row = try XCTUnwrap(ledger.load().first { $0.pushId == fired.pushId }, file: file, line: line)
        XCTAssertNil(row.removedReason, "a fired push is not taken back", file: file, line: line)
        XCTAssertEqual(row.deliveredAt, fired.scheduledFor, file: file, line: line)
        XCTAssertFalse(active.contains { $0.belongsTo == fired.belongsTo }, "its day is not pushed again",
                       file: file, line: line)
    }

    func testTimeZoneTakeBackKeepsAFiredPushDelivered() async throws {
        let (scheduler, tonight) = try await fireTonight(after: 2 * 3600)
        zone.zone = TimeZone(identifier: "America/New_York")!
        await scheduler.appBecameActive()
        XCTAssertEqual(log.runs().first?.trigger, "timeZone")
        try assertDelivered(tonight)
    }

    func testReplanKeepsAFiredPushDelivered() async throws {
        let (scheduler, tonight) = try await fireTonight(after: 600)
        await scheduler.replan()
        try assertDelivered(tonight)
    }

    func testFewerLikeThisKeepsAFiredPushOfTheBucketDelivered() async throws {
        let (scheduler, tonight) = try await fireTonight(after: 600)
        let other = try XCTUnwrap(active.last)
        XCTAssertEqual(other.bucket, tonight.bucket)
        await scheduler.menu(.fewerLikeThis, pushId: other.pushId)
        XCTAssertEqual(ledger.load().first { $0.pushId == other.pushId }?.removedReason, .menuBucket)
        try assertDelivered(tonight)
    }

    func testNotThisDayKeepsAFiredPushOfTheDayDelivered() async throws {
        let (scheduler, tonight) = try await fireTonight(after: 600)
        await scheduler.menu(.notThisDay, pushId: tonight.pushId)
        XCTAssertNotNil(preferences.load().blockedDays[tonight.belongsTo])
        try assertDelivered(tonight)
    }
}

// MARK: - Day keys across a time-zone change

/// Belongs-to days are local dates of the zone of the run that wrote them:
/// after a zone change the same photos may fall on another day. A delivered
/// or blocked push still rules its photos out.
final class PushSchedulerZoneDayTests: PushSchedulerTestCase {
    func testDeliveredPhotosAreNotPushedAgainAfterAZoneChange() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        clock.now = tonight.scheduledFor.addingTimeInterval(3600)
        notifier.pendingIds.remove(tonight.identifier)
        await scheduler.markOpened(tonight.pushId)
        zone.zone = TimeZone(identifier: "Pacific/Honolulu")!
        XCTAssertNotEqual(day("g0"), tonight.belongsTo, "the group falls on another day in the new zone")
        await scheduler.appBecameActive()
        XCTAssertFalse(active.contains { !Set($0.photoIds).isDisjoint(with: tonight.photoIds) },
                       "the same photos pushed twice")
    }

    func testBlockedPhotosStayBlockedAfterAZoneChange() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let first = try XCTUnwrap(active.first)
        await scheduler.menu(.notThisDay, pushId: first.pushId)
        XCTAssertEqual(preferences.load().blockedPhotos[first.belongsTo], first.photoIds)
        clock.advance(600)
        zone.zone = TimeZone(identifier: "Pacific/Honolulu")!
        await scheduler.appBecameActive()
        XCTAssertEqual(log.runs().first?.trigger, "timeZone")
        XCTAssertFalse(active.contains { !Set($0.photoIds).isDisjoint(with: first.photoIds) },
                       "a blocked day pushed after all")
    }
}

// MARK: - A time-zone change while a run plans

/// The zone changes while a run is scheduling its nights (the process lived
/// in the background): the old run stops writing, and every push left is
/// on a slot of the new zone.
final class PushSchedulerZoneChangeMidRunTests: PushSchedulerTestCase {
    /// Moves to Shanghai and returns to the front while the second night's
    /// notification is being added.
    private func changeZoneAtSecondSchedule(_ scheduler: PushScheduler) {
        let calls = CallCounter()
        let zone = self.zone!
        notifier.onSchedule = {
            guard calls.bump() == 2 else { return }
            zone.zone = TimeZone(identifier: "Asia/Shanghai")!
            await scheduler.appBecameActive()
        }
    }

    private func assertOnNewZoneSlots(file: StaticString = #filePath, line: UInt = #line) {
        notifier.onSchedule = nil
        let slots = Set(PushSlots.make(now: clock.now, calendar: zone.calendar))
        XCTAssertEqual(active.count, 7, file: file, line: line)
        XCTAssertTrue(active.allSatisfy { slots.contains($0.scheduledFor) }, "every push on a new-zone slot",
                      file: file, line: line)
        let ours = notifier.pendingIds.filter(PushIdentifier.isOurs)
        XCTAssertEqual(ours, Set(active.map(\.identifier)), "no old-zone request left", file: file, line: line)
        XCTAssertEqual(state.load().timeZoneId, "Asia/Shanghai", file: file, line: line)
        XCTAssertEqual(log.runs().first?.trigger, "timeZone", file: file, line: line)
    }

    func testZoneChangeDuringTheFirstRun() async throws {
        let scheduler = makeScheduler()
        changeZoneAtSecondSchedule(scheduler)
        await scheduler.appBecameActive()
        assertOnNewZoneSlots()
    }

    func testZoneChangeDuringALaterRun() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        XCTAssertEqual(state.load().timeZoneId, "America/Chicago")
        clock.advance(600)
        changeZoneAtSecondSchedule(scheduler)
        await scheduler.replan()
        assertOnNewZoneSlots()
    }
}

// MARK: - A request the ledger never heard of

/// Killed between adding a night's notification and writing its ledger
/// row: the next run takes the request back, or the night gets two pushes.
final class PushSchedulerOrphanRequestTests: PushSchedulerTestCase {
    func testRequestWithoutALedgerRowIsTakenBack() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        let record = try XCTUnwrap(records.load(tonight.pushId))
        let orphan = PushRecord(pushId: "killed", memory: record.memory, photoIds: record.photoIds,
                                createdAt: clock.now, rank: 1, score: 0.5, bucket: record.bucket)
        try records.save(orphan)
        notifier.pendingIds.formUnion(["pt.killed", "other.x"])
        clock.advance(2 * 3600)
        await scheduler.appBecameActive()
        XCTAssertTrue(notifier.removedPending.contains("pt.killed"))
        XCTAssertNil(records.load("killed"))
        XCTAssertTrue(notifier.pendingIds.contains("other.x"), "another feature's request is never touched")
        XCTAssertFalse(notifier.removedPending.contains("other.x"))
        XCTAssertEqual(notifier.pendingIds.filter(PushIdentifier.isOurs), Set(active.map(\.identifier)))
    }

    /// A debug push between its notification and its ledger row is not an
    /// orphan: a run reconciling meanwhile leaves it.
    func testDebugPushBeingAddedIsLeftAlone() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let calls = CallCounter()
        notifier.onSchedule = {
            guard calls.bump() == 1 else { return }
            await scheduler.replan()
        }
        let result = await scheduler.previewNext()
        notifier.onSchedule = nil
        guard case .scheduled = result else { return XCTFail("previewed") }
        let debug = try XCTUnwrap(ledger.load().first(where: \.isDebug))
        XCTAssertTrue(notifier.pendingIds.contains(debug.identifier))
        XCTAssertFalse(notifier.removedPending.contains(debug.identifier))
        XCTAssertEqual(log.runs().first?.trigger, "replan", "a run reconciled while it was added")
    }
}
