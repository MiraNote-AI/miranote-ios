import XCTest
@testable import MiraNoteKit

/// The debug page: previews, trying groups outside the schedule, replan,
/// clear all, and the snapshot it reads.
final class PushSchedulerDebugTests: PushSchedulerTestCase {
    /// g7 and g8: two food groups the seven nights leave out.
    private func addOutside() {
        for (prefix, days) in [("g7", 10.0), ("g8", 11.0)] {
            library.add(prefix, start: start.addingTimeInterval(-days * 86_400 - 6 * 3600), count: 3)
        }
    }

    private func press(_ scheduler: PushScheduler) async -> [TriggerProgress] {
        var steps: [TriggerProgress] = []
        for await step in await scheduler.tryOutside() { steps.append(step) }
        return steps
    }

    private func asked(_ steps: [TriggerProgress]) -> [String] {
        steps.compactMap { if case .askingAI(_, let date, _, _) = $0 { return date } else { return nil } }
    }

    func testPreviewCyclesAndDoesNotChangeSchedule() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let before = active
        let pressedAt = clock.now
        var days: [PreviewResult] = []
        for _ in 0..<8 { days.append(await scheduler.previewNext()) }
        let slotDays = PushSlots.make(now: start, calendar: zone.calendar).map {
            PreviewResult.scheduled(slotDay: SchedulePlanner.day($0, calendar: zone.calendar))
        }
        XCTAssertEqual(days, slotDays + [slotDays[0]], "the Nth press sends the Nth night, then wraps")
        XCTAssertEqual(active, before, "the schedule is untouched")
        let debug = ledger.load().filter(\.isDebug)
        XCTAssertEqual(debug.count, 8)
        XCTAssertTrue(debug.allSatisfy { $0.scheduledFor == pressedAt.addingTimeInterval(10) })
        let copy = try XCTUnwrap(records.load(debug[0].pushId))
        let original = try XCTUnwrap(records.load(before[0].pushId))
        XCTAssertEqual(copy.memory, original.memory, "same memory, no AI")
        XCTAssertEqual(copy.isDebug, true)
        XCTAssertNotEqual(copy.pushId, original.pushId)
        XCTAssertEqual(notifier.scheduledAt.suffix(8).filter { $0 == nil }.count, 8, "10 s out")
        XCTAssertEqual(client.submitted.count, 7)

        clock.advance(60)
        notifier.pendingIds.subtract(debug.map(\.identifier))
        clock.advance(3600)
        await scheduler.appBecameActive()
        XCTAssertTrue(ledger.load().filter(\.isDebug).allSatisfy { $0.deliveredAt != nil })
        XCTAssertTrue(LedgerReconciler.pushedDays(ledger.load()).isEmpty, "a debug push never counts as pushed")
        XCTAssertEqual(active, before)
    }

    func testPreviewWithNothingScheduled() async {
        library.assetsList = []
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let result = await scheduler.previewNext()
        XCTAssertEqual(result, .nothingScheduled)
        XCTAssertTrue(notifier.scheduled.isEmpty)
    }

    func testTryOutsideStartsAfterTheSchedule() async throws {
        addOutside()
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let before = active
        let first = await press(scheduler)
        XCTAssertEqual(first.first, .preparing)
        XCTAssertEqual(asked(first), [TriggerWords.shortDate(day("g7"))], "the first group outside the nights")
        guard case .scheduled(1, _) = first.last else { return XCTFail("\(first)") }
        let second = await press(scheduler)
        XCTAssertEqual(asked(second), [TriggerWords.shortDate(day("g8"))])
        XCTAssertEqual(active, before, "trying outside never changes the schedule")
        let debug = ledger.load().filter(\.isDebug)
        XCTAssertEqual(debug.map(\.belongsTo), [day("g7"), day("g8")])
        XCTAssertTrue(try debug.allSatisfy { try XCTUnwrap(records.load($0.pushId)).isDebug == true })
        let key = AIResultCache.key((0..<3).map { "g7-\($0)" })
        guard case .ok = cache.verdict(key) else { return XCTFail("the answer is cached") }
    }

    /// The fake AI's words for a group outside are never cached; with the
    /// switch off the backend is asked, even when an older build cached
    /// them.
    func testTryOutsideNeverReusesFakeWords() async throws {
        addOutside()
        fake = true
        let faked = makeScheduler()
        await faked.appBecameActive()
        let first = await press(faked)
        guard case .scheduled(1, _) = first.last else { return XCTFail("\(first)") }
        XCTAssertTrue(client.submitted.isEmpty)
        XCTAssertTrue(cache.verdicts().isEmpty, "the fake AI's words never enter the cache")
        let debug = try XCTUnwrap(ledger.load().first(where: \.isDebug))
        let record = try XCTUnwrap(records.load(debug.pushId))
        XCTAssertTrue(record.memory.isFakeMade)
        let key = AIResultCache.key((0..<3).map { "g7-\($0)" })
        try cache.store(.ok(memory: record.memory, photoIds: record.photoIds), key: key, belongsTo: day("g7"),
                        at: clock.now)

        fake = false
        let real = makeScheduler()
        let second = await press(real)
        XCTAssertEqual(asked(second), [TriggerWords.shortDate(day("g7"))])
        guard case .scheduled(1, _) = second.last else { return XCTFail("\(second)") }
        XCTAssertEqual(client.submitted, [day("g7")], "the backend is asked")
        guard case .ok(let memory, _) = cache.verdict(key) else { return XCTFail("the answer is cached") }
        XCTAssertFalse(memory.isFakeMade)
    }

    func testTryOutsideWrapsWithNotice() async throws {
        addOutside()
        client.scripts[day("g8")] = [.rejected]
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        _ = await press(scheduler)
        let second = await press(scheduler)
        XCTAssertEqual(second.filter { $0 == .wrapped }.count, 1, "past g8: back to g7 with a notice")
        XCTAssertTrue(second.contains(.rejected(rank: 2, message: "no \(day("g8"))", next: 1)))
        XCTAssertEqual(asked(second), [day("g8"), day("g7")].map(TriggerWords.shortDate))
        guard case .scheduled(1, _) = second.last else { return XCTFail("\(second)") }
        XCTAssertEqual(client.submitted.filter { $0 == day("g7") }.count, 1, "g7 again from the cache")
        let third = await press(scheduler)
        XCTAssertTrue(third.contains(.rejected(rank: 2, message: "no \(day("g8"))", next: 1)),
                      "the cached refusal is shown")
        XCTAssertEqual(client.submitted.filter { $0 == day("g8") }.count, 1)
    }

    func testTryOutsideWithNotificationsOff() async {
        let scheduler = makeScheduler()
        notifier.allowed = false
        let steps = await press(scheduler)
        XCTAssertEqual(steps, [.preparing, .failed(.notificationsOff)])
    }

    func testOnlyOurIdentifiersAreRemoved() async throws {
        notifier.pendingIds.insert("other.x")
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        _ = await scheduler.previewNext()
        await scheduler.menu(.notThisDay, pushId: try XCTUnwrap(active.first).pushId)
        await scheduler.replan()
        zone.zone = TimeZone(identifier: "Asia/Shanghai")!
        await scheduler.appBecameActive()
        clock.advance(3 * 86_400)
        await scheduler.appBecameActive()
        await scheduler.clearAll()
        XCTAssertFalse(notifier.removedPending.contains("other.x"))
        XCTAssertFalse(notifier.removedDelivered.contains("other.x"))
        XCTAssertTrue(notifier.removedPending.allSatisfy(PushIdentifier.isOurs))
        XCTAssertTrue(notifier.removedDelivered.allSatisfy(PushIdentifier.isOurs))
        XCTAssertTrue(notifier.pendingIds.contains("other.x"))
        XCTAssertEqual(notifier.pendingIds, ["other.x"], "clear all took back every one of ours")
    }

    func testReplanKeepsLedgerPreferencesAndCache() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let before = active
        await scheduler.replan()
        let entries = ledger.load()
        XCTAssertTrue(before.allSatisfy { old in entries.first { $0.pushId == old.pushId }?.removedReason == .replan })
        XCTAssertEqual(active.count, 7)
        XCTAssertEqual(client.submitted.count, 7, "the cache answers the replan")
        XCTAssertEqual(log.runs().first?.trigger, "replan")
    }

    func testClearAllForgetsAllButTheAnalyses() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        _ = await scheduler.previewNext()
        await scheduler.menu(.notThisDay, pushId: try XCTUnwrap(active.first).pushId)
        await scheduler.clearAll()
        XCTAssertTrue(ledger.load().isEmpty)
        XCTAssertEqual(preferences.load(), PushPreferences())
        XCTAssertTrue(cache.verdicts().isEmpty)
        XCTAssertTrue(log.runs().isEmpty)
        XCTAssertEqual(state.load(), SchedulerState())
        XCTAssertTrue(records.all().isEmpty)
        XCTAssertNil(lastRun.load())
        let analyses = AnalysisStore(directory: folder.appendingPathComponent("analysis"))
        XCTAssertEqual(analyses.analyzedIds().count, 42, "Vision results are kept")
        let snapshot = await scheduler.snapshot()
        XCTAssertTrue(snapshot.groups.isEmpty)
        let preview = await scheduler.previewNext()
        XCTAssertEqual(preview, .nothingScheduled)
        await scheduler.appBecameActive()
        XCTAssertEqual(active.count, 7, "the next return to the front plans like a first launch")
    }

    func testSnapshotShowsNightsGroupsAndReport() async throws {
        client.scripts[day("g0")] = [.rejected]
        client.scripts[day("g1")] = [.timeoutError]
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let snapshot = await scheduler.snapshot()
        XCTAssertEqual(snapshot.days.count, 7)
        XCTAssertEqual(snapshot.days[1].entry, nil)
        XCTAssertEqual(snapshot.days[1].emptyReason, "aiError")
        XCTAssertEqual(snapshot.days[0].emptyReason, "noCandidate", "g0 turned down, every other group taken")
        XCTAssertEqual(snapshot.days.compactMap(\.entry).count, 5)
        XCTAssertEqual(snapshot.groups.count, 7)
        let rejected = try XCTUnwrap(snapshot.groups.first { $0.report.belongsTo == day("g0") })
        XCTAssertEqual(rejected.aiStatus, .rejected("no \(day("g0"))"))
        XCTAssertEqual(rejected.report.ineligible, .aiRejected)
        XCTAssertNil(rejected.scheduledDay)
        let errored = try XCTUnwrap(snapshot.groups.first { $0.report.belongsTo == day("g1") })
        XCTAssertEqual(errored.aiStatus, .notSent)
        let scheduled = try XCTUnwrap(snapshot.groups.first { $0.report.belongsTo == day("g2") })
        XCTAssertEqual(scheduled.aiStatus, .ok)
        XCTAssertNotNil(scheduled.scheduledDay)
        XCTAssertEqual(scheduled.report.rawCount, 7)
        XCTAssertEqual(scheduled.report.uniqueCount, 7)
        XCTAssertEqual(scheduled.report.bucket, .food)
        XCTAssertNotNil(scheduled.report.score)
        XCTAssertEqual(snapshot.runs.count, 1)
        XCTAssertEqual(snapshot.categories.buckets.first { $0.bucket == .food }?.count, 42)
        XCTAssertEqual(snapshot.categories.buckets.first?.examples.count, CategoryReport.maxExamples)
        XCTAssertNotNil(snapshot.threshold)

        let relaunched = makeScheduler()
        let again = await relaunched.snapshot()
        XCTAssertEqual(again.groups.count, 7, "the last run's groups survive a relaunch")
        XCTAssertEqual(again.days[1].emptyReason, "aiError")
    }

    /// Under 30 min to tonight's slot it is no longer one of the seven
    /// nights, but its push is still to come: the page keeps showing it.
    func testSnapshotKeepsTonightsPushUnderHalfAnHourAway() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        clock.now = tonight.scheduledFor.addingTimeInterval(-20 * 60)
        var snapshot = await scheduler.snapshot()
        XCTAssertEqual(snapshot.days.count, 8, "tonight, then the next seven nights")
        XCTAssertEqual(snapshot.days.first?.entry, tonight)
        XCTAssertEqual(snapshot.days.first?.slot, tonight.scheduledFor)
        XCTAssertEqual(Set(snapshot.days.map(\.slotDay)).count, 8)

        clock.now = tonight.scheduledFor.addingTimeInterval(60)
        snapshot = await scheduler.snapshot()
        XCTAssertEqual(snapshot.days.count, 7, "gone once it has gone out")
        XCTAssertFalse(snapshot.days.contains { $0.entry?.pushId == tonight.pushId })
    }

    func testLastRunLoadsEmptyFromGarbage() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("[1,".utf8).write(to: folder.appendingPathComponent("last-run.json"))
        XCTAssertNil(lastRun.load())
        let report = LastRunReport(finishedAt: start, emptyDays: ["2025-10-31": "noCandidate"], fragments: [],
                                   utility: ["u"], categories: .empty, threshold: nil)
        try lastRun.save(report)
        XCTAssertEqual(lastRun.load(), report)
        try lastRun.clear()
        XCTAssertNil(lastRun.load())
    }

    func testCategoryReportCountsOtherLabels() {
        let analyses = ["a": PhotoAnalysis(id: "a", labels: ["art", "decoration"], broad: [.art], faces: 0,
                                           aesthetics: nil, isUtility: false, featurePrint: nil),
                        "b": PhotoAnalysis(id: "b", labels: ["art"], broad: [.art], faces: 0, aesthetics: nil,
                                           isUtility: false, featurePrint: nil),
                        "c": PhotoAnalysis(id: "c", labels: ["sky"], broad: [.sky], faces: 0, aesthetics: nil,
                                           isUtility: false, featurePrint: nil)]
        let report = CategoryReport.make(ids: ["c", "b", "a"], analyses: analyses)
        XCTAssertEqual(report.buckets.map(\.bucket), PushBucket.allCases)
        XCTAssertEqual(report.buckets.first { $0.bucket == .other }?.examples, ["b", "a"])
        XCTAssertEqual(report.buckets.first { $0.bucket == .scenery }?.count, 1)
        XCTAssertEqual(report.otherLabels, [.init(label: "art", count: 2), .init(label: "decoration", count: 1)])
    }
}

/// The debug page's clears: a preference cleared refills the nights, and
/// "clear all" empties the stores before it waits on the system.
final class PushSchedulerDebugClearTests: PushSchedulerTestCase {
    /// Clearing a blocked day or a "fewer" on the debug page refills the
    /// nights at once.
    func testUnblockingADayReplans() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let target = try XCTUnwrap(active.first { $0.belongsTo == day("g2") })
        await scheduler.menu(.notThisDay, pushId: target.pushId)
        XCTAssertFalse(activeDays.contains(day("g2")))
        clock.advance(600)
        await scheduler.unblockDay(day("g2"))
        XCTAssertEqual(preferences.load(), PushPreferences())
        XCTAssertEqual(log.runs().first?.trigger, "replan")
        XCTAssertTrue(activeDays.contains(day("g2")), "the day is planned again")
    }

    func testClearingFewerReplans() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        await scheduler.menu(.fewerLikeThis, pushId: try XCTUnwrap(active.first).pushId)
        XCTAssertTrue(active.isEmpty, "every group is food")
        clock.advance(600)
        await scheduler.clearFewer(.food)
        XCTAssertEqual(log.runs().first?.trigger, "replan")
        XCTAssertEqual(activeDays, allSeven)
    }

    /// The stores are empty before the first await of a clear: nothing in
    /// flight meanwhile reads the old ledger or writes into the cleared one.
    func testClearAllWipesTheStoresBeforeWaitingOnTheSystem() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let ledger = self.ledger
        let records = self.records
        let seen = SleepLog()
        notifier.onPendingOnce = {
            seen.record(ledger.load().isEmpty && records.all().isEmpty ? 1 : 0)
        }
        await scheduler.clearAll()
        XCTAssertEqual(seen.durations, [1])
        XCTAssertTrue(notifier.pendingIds.filter(PushIdentifier.isOurs).isEmpty, "every request still taken back")
    }
}

extension PushSchedulerDebugTests {
    /// Device test 11-05: three presses, the app closed between them, all
    /// sent the first night. Where the last preview stopped is in the
    /// ledger, so a relaunch goes on from there.
    func testPreviewGoesOnAfterARelaunch() async {
        await makeScheduler().appBecameActive()
        let slotDays = PushSlots.make(now: start, calendar: zone.calendar).map {
            PreviewResult.scheduled(slotDay: SchedulePlanner.day($0, calendar: zone.calendar))
        }
        var days: [PreviewResult] = []
        for _ in 0..<3 { days.append(await makeScheduler().previewNext()) }
        XCTAssertEqual(days, Array(slotDays.prefix(3)))

        // A "try outside" push in between is not a night: the next preview
        // still follows the last night previewed.
        addOutside()
        _ = await press(makeScheduler())
        let next = await makeScheduler().previewNext()
        XCTAssertEqual(next, slotDays[3])
    }
}
