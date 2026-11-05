import XCTest
@testable import MiraNoteKit

/// The AI wave: parallel submits, one batch poll per 15 s, each answer acted on.
final class PushSchedulerAITests: PushSchedulerTestCase {
    func testFirstRunSchedulesSevenNightsInParallel() async throws {
        for group in allSeven { client.scripts[group] = [.running, .ok] }
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        XCTAssertEqual(Array(client.events.prefix(7)).filter { $0.hasPrefix("submit") }.count, 7,
                       "every night submitted before the first poll: \(client.events)")
        XCTAssertEqual(Set(client.submitted), Set(allSeven))
        XCTAssertEqual(sleeps.durations, [15, 15])
        XCTAssertEqual(client.pollManyCount, 2, "one batch poll per 15 s")
        XCTAssertEqual(activeDays, allSeven)
        XCTAssertTrue(notifier.scheduledIdentifiers.allSatisfy { $0.hasPrefix("pt.") })
        let times = notifier.scheduledAt.compactMap { $0 }.map { "\($0.day!) \($0.hour!):\($0.minute!)" }
        XCTAssertEqual(Set(times), ["31 21:0", "1 20:30", "2 20:30", "3 21:0", "4 21:0", "5 21:0", "6 21:0"])
        let run = try XCTUnwrap(log.runs().first)
        XCTAssertEqual(run.trigger, "foreground")
        XCTAssertEqual(run.aiSent, 7)
        XCTAssertEqual(run.scheduledDays.count, 7)
        XCTAssertEqual(run.emptyDays, [:])
        XCTAssertEqual(run.groups.filter { $0.outcome == .ok }.count, 7)
        XCTAssertTrue(state.load().outstanding.isEmpty, "answered jobs are forgotten")
    }

    func testOkSchedulesItsDayAtOnce() async {
        for group in allSeven.dropFirst() { client.scripts[group] = [.running, .running, .ok] }
        let notifier = self.notifier!
        let counts = SleepLog()
        hook.action = { number in if number == 2 { counts.record(Double(notifier.scheduled.count)) } }
        await makeScheduler().appBecameActive()
        XCTAssertEqual(counts.durations, [1], "tonight scheduled before the others came back")
        XCTAssertEqual(activeDays, allSeven)
    }

    func testRejectedTriesNextForThatDay() async throws {
        library.add("g7", start: start.addingTimeInterval(-10 * 86_400), count: 3)
        client.scripts[day("g0")] = [.rejected]
        await makeScheduler().appBecameActive()
        XCTAssertEqual(activeDays, groups(["g7", "g1", "g2", "g3", "g4", "g5", "g6"]),
                       "tonight takes the next group no other night has")
        let key = AIResultCache.key((0..<9).map { "g0-\($0)" })
        guard case .rejected = cache.verdict(key) else { return XCTFail("refusal cached") }
        let run = try XCTUnwrap(log.runs().first)
        XCTAssertEqual(run.groups.first { $0.outcome == .rejected }?.belongsTo, day("g0"))
    }

    func testErrorLeavesTheDayAndKeepsExisting() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let before = active
        addBest()
        client.scripts[day("n")] = [.timeoutError]
        clock.advance(3600)
        await scheduler.appBecameActive()
        XCTAssertEqual(active, before, "the error changed nothing")
        let run = try XCTUnwrap(log.runs().first)
        XCTAssertEqual(run.groups.first { $0.belongsTo == day("n") }?.outcome, .error)
        XCTAssertEqual(run.emptyDays, [:])
        XCTAssertEqual(client.submitted.filter { $0 == day("n") }.count, 1, "the night is not given another group")
    }

    func testErrorWithoutExistingLeavesTheNightEmpty() async throws {
        client.scripts[day("g0")] = [.timeoutError]
        await makeScheduler().appBecameActive()
        let run = try XCTUnwrap(log.runs().first)
        XCTAssertEqual(run.emptyDays.values.sorted(), ["aiError"])
        XCTAssertTrue(state.load().lastRunLeftDaysUnfilled)
        XCTAssertFalse(activeDays.contains(day("g0")))
    }

    func testExpiredJobResubmittedOnce() async throws {
        client.scripts[day("g0")] = [.running, .expired]
        await makeScheduler().appBecameActive()
        XCTAssertEqual(client.submitted.filter { $0 == day("g0") }.count, 2)
        let run = try XCTUnwrap(log.runs().first)
        XCTAssertEqual(run.groups.first { $0.belongsTo == day("g0") }?.message, "aiTimeout")
        XCTAssertEqual(run.emptyDays.count, 1)
    }

    func testJobBudgetIsSixMinutes() async throws {
        client.scripts[day("g0")] = [.running]
        await makeScheduler().appBecameActive()
        XCTAssertEqual(sleeps.durations.reduce(0, +), 360)
        XCTAssertEqual(log.runs().first?.emptyDays.values.sorted(), ["aiError"])
    }

    /// Slow photo reads (iCloud downloads) before the submit do not use up
    /// the 6 minutes the job has to answer.
    func testPhotoReadsDoNotUseTheJobBudget() async throws {
        library = FakeLibrary(now: start, groups: [9])
        let clock = self.clock!
        library.onRead = { _ in clock.advance(50) }
        await makeScheduler().appBecameActive()
        XCTAssertEqual(activeDays, [day("g0")], "nine reads of 50 s, then the answer at the first poll")
        let outcome = try XCTUnwrap(log.runs().first?.groups.first)
        XCTAssertEqual(outcome.outcome, .ok)
        XCTAssertLessThan(outcome.seconds, 60, "timed from the submit")
    }

    func testRateLimitWaitsTenSeconds() async {
        client.scripts[day("g0")] = [.rateLimited, .ok]
        await makeScheduler().appBecameActive()
        XCTAssertEqual(sleeps.durations, [15, 10, 15])
        XCTAssertEqual(activeDays, allSeven)
    }

    /// C9: after a relaunch the job submitted earlier is polled, not sent again.
    func testRelaunchPollsTheOutstandingJob() async throws {
        let ids = (0..<9).map { "g0-\($0)" }
        let meta = ComposeMeta(groupKey: "k", date: day("g0"), weekday: 1, startTime: "", endTime: "", place: nil,
                               rawCount: 9, coversAll: true, recentQuestionTypes: [], bucket: "food", tz: "",
                               photos: [])
        let job = try await client.submit(meta, photos: [])
        try state.update {
            $0.outstanding[AIResultCache.key(ids)] = OutstandingJob(
                jobId: job, submittedAt: start.addingTimeInterval(-600), slotDay: "2025-10-31")
        }
        await makeScheduler().appBecameActive()
        XCTAssertEqual(client.submitted.filter { $0 == day("g0") }.count, 1, "only the earlier submit")
        XCTAssertEqual(activeDays, allSeven)
        XCTAssertTrue(state.load().outstanding.isEmpty)
    }

    /// C9: a job older than an hour is not polled; the group is submitted anew.
    func testJobOlderThanAnHourIsSubmittedAgain() async throws {
        let ids = (0..<9).map { "g0-\($0)" }
        let meta = ComposeMeta(groupKey: "k", date: day("g0"), weekday: 1, startTime: "", endTime: "", place: nil,
                               rawCount: 9, coversAll: true, recentQuestionTypes: [], bucket: "food", tz: "",
                               photos: [])
        let job = try await client.submit(meta, photos: [])
        try state.update {
            $0.outstanding[AIResultCache.key(ids)] = OutstandingJob(
                jobId: job, submittedAt: start.addingTimeInterval(-3700), slotDay: "2025-10-31")
        }
        await makeScheduler().appBecameActive()
        XCTAssertEqual(client.submitted.filter { $0 == day("g0") }.count, 2, "the earlier submit and a new one")
        XCTAssertEqual(try XCTUnwrap(log.runs().first).aiSent, 7, "g0 went out again")
        XCTAssertEqual(activeDays, allSeven, "g0's night is scheduled from the new result")
        XCTAssertTrue(state.load().outstanding.isEmpty)
        XCTAssertEqual(log.counters().leftBeforeResult, 0)
    }

    /// E4: one real run's log entry carries every field.
    func testScheduleRunCarriesEveryField() async throws {
        client.scripts[day("g0")] = [.running, .rejected]
        client.scripts[day("g1")] = [.running, .ok]
        await makeScheduler().appBecameActive()
        let run = try XCTUnwrap(log.runs().first)
        XCTAssertEqual(run.startedAt, start)
        XCTAssertEqual(run.finishedAt, clock.now)
        XCTAssertLessThan(run.startedAt, run.finishedAt)
        XCTAssertEqual(run.trigger, "foreground")
        XCTAssertGreaterThan(run.fragments, 0)
        XCTAssertGreaterThan(run.candidates, 0)
        XCTAssertGreaterThan(run.aiSent, 0)
        XCTAssertNil(run.error)
        let rejected = try XCTUnwrap(run.groups.first { $0.belongsTo == day("g0") })
        XCTAssertEqual(rejected.outcome, .rejected)
        XCTAssertGreaterThan(rejected.seconds, 0, "the seconds from submit to answer")
        XCTAssertEqual(try XCTUnwrap(run.groups.first { $0.belongsTo == day("g1") }).outcome, .ok)
        XCTAssertFalse(run.scheduledDays.isEmpty)
        XCTAssertFalse(run.emptyDays.isEmpty, "the night g0's refusal left empty")
        XCTAssertTrue(run.emptyDays.values.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(run.scheduledDays).union(run.emptyDays.keys).count, 7)
    }

    func testLeftBeforeResultCounts() async throws {
        for group in allSeven { client.scripts[group] = [.running, .running, .ok] }
        let scheduler = makeScheduler()
        let state = self.state
        let flags = SleepLog()
        hook.action = { number in
            guard number == 1 else { return }
            await scheduler.appEnteredBackground()
            await scheduler.backgroundTimeExpired()
            flags.record(state.load().lastRunLeftDaysUnfilled ? 1 : 0)
        }
        await scheduler.appBecameActive()
        XCTAssertEqual(log.counters().leftBeforeResult, 7)
        XCTAssertEqual(flags.durations, [1], "marked unfilled at once, in case iOS ends the app")
        let run = try XCTUnwrap(log.runs().first)
        XCTAssertEqual(run.groups.filter { $0.outcome == .left }.count, 7)
        XCTAssertEqual(activeDays, allSeven, "the process lived: polling went on")
    }

    func testLeftBeforeResultEmptyNightSaysSo() async throws {
        client.scripts[day("g0")] = [.running, .timeoutError]
        let scheduler = makeScheduler()
        hook.action = { number in if number == 1 { await scheduler.backgroundTimeExpired() } }
        await scheduler.appBecameActive()
        XCTAssertEqual(log.runs().first?.emptyDays.values.sorted(), ["leftBeforeResult"])
        XCTAssertTrue(state.load().lastRunLeftDaysUnfilled)
    }
}
