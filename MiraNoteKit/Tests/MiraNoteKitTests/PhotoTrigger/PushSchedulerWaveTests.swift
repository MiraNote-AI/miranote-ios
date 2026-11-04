import XCTest
@testable import MiraNoteKit

/// The AI wave's bounds (review round 1): a refusal is never sent again,
/// the 6-minute budget holds whatever the backend answers, the hour lock
/// holds at replacement time, and nothing is left behind by a failed
/// schedule or a clear.
final class PushSchedulerWaveTests: PushSchedulerTestCase {
    func testTwoNightsRejectedInOnePollAreNotResent() async throws {
        library.add("g7", start: start.addingTimeInterval(-10 * 86_400), count: 3)
        client.scripts[day("g0")] = [.running, .rejected]
        client.scripts[day("g1")] = [.running, .rejected]
        await makeScheduler().appBecameActive()
        XCTAssertEqual(client.submitted.filter { $0 == day("g0") }.count, 1)
        XCTAssertEqual(client.submitted.filter { $0 == day("g1") }.count, 1, "g1's refusal is not asked again")
        XCTAssertEqual(client.submitted.filter { $0 == day("g7") }.count, 1)
        XCTAssertEqual(activeDays.first, day("g7"), "tonight takes the next group no one turned down")
        XCTAssertFalse(activeDays.contains(day("g1")))
        let key = AIResultCache.key((0..<8).map { "g1-\($0)" })
        guard case .rejected = cache.verdict(key) else { return XCTFail("the refusal stays cached") }
    }

    func testSteadyRateLimitEndsTheRunAndRerunStarts() async throws {
        for group in allSeven { client.scripts[group] = [.rateLimited] }
        let scheduler = makeScheduler()
        hook.action = { number in if number == 1 { await scheduler.replan() } }
        await scheduler.appBecameActive()
        let running = await scheduler.isRunning
        XCTAssertFalse(running, "the run ended")
        let runs = log.runs()
        XCTAssertEqual(runs.count, 2, "the folded rerun ran")
        XCTAssertEqual(runs.last?.trigger, "foreground")
        XCTAssertEqual(runs.first?.trigger, "replan")
        for run in runs {
            XCTAssertEqual(run.emptyDays.count, 7)
            XCTAssertEqual(Set(run.emptyDays.values), ["aiError"])
            XCTAssertLessThanOrEqual(run.finishedAt.timeIntervalSince(run.startedAt), 360 + 25)
        }
    }

    func testNoReplacementWhenTheWaveRunsIntoTheLock() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        addBest()
        clock.now = tonight.scheduledFor.addingTimeInterval(-2 * 3600)
        client.scripts[day("n")] = [.running, .ok]
        let clock = self.clock!
        let fired = SleepLog()
        hook.action = { _ in
            guard fired.durations.isEmpty else { return }
            fired.record(1)
            clock.advance(3600)
        }
        await scheduler.appBecameActive()
        XCTAssertEqual(fired.durations, [1])
        XCTAssertEqual(active.first, tonight, "an hour from firing by the time n passed: kept")
        XCTAssertFalse(ledger.load().contains { $0.removedReason == .replaced })
        XCTAssertFalse(activeDays.contains(day("n")))
    }

    func testRefusedScheduleLeavesNoRecord() async throws {
        notifier.refuseSchedule = true
        await makeScheduler().appBecameActive()
        XCTAssertTrue(records.all().isEmpty, "no record without its notification")
        XCTAssertTrue(ledger.load().isEmpty)
        XCTAssertEqual(Set(log.runs().first.map { Array($0.emptyDays.values) } ?? []), ["notificationsOff"])
    }

    func testClearDuringScheduleTakesThePushBack() async throws {
        let scheduler = makeScheduler()
        notifier.onSchedule = { await scheduler.clearAll() }
        await scheduler.appBecameActive()
        XCTAssertTrue(ledger.load().isEmpty, "no ledger row for a push scheduled across a clear")
        XCTAssertTrue(records.all().isEmpty)
        XCTAssertTrue(notifier.pendingIds.isEmpty, "the push is taken back")
        XCTAssertTrue(log.runs().isEmpty)
    }

    func testStaleOutstandingJobsArePruned() async throws {
        try state.update {
            $0.outstanding["old"] = OutstandingJob(jobId: "j", submittedAt: start.addingTimeInterval(-7200),
                                                   slotDay: "2025-10-30")
        }
        await makeScheduler().appBecameActive()
        XCTAssertNil(state.load().outstanding["old"])
    }

    func testReturnToTheFrontRestartsTheBudget() async throws {
        client.scripts[day("g0")] = [.running, .running, .ok]
        let scheduler = makeScheduler()
        let clock = self.clock!
        hook.action = { number in
            guard number == 1 else { return }
            await scheduler.appEnteredBackground()
            clock.advance(3000)
            await scheduler.appBecameActive()
        }
        await scheduler.appBecameActive()
        XCTAssertEqual(activeDays, allSeven, "suspended time does not use up the budget")
    }
}
