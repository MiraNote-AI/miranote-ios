import XCTest
@testable import MiraNoteKit

/// The scheduler composing the scheduled pushes again once the copy rules
/// change (handoff refine 5.4, acceptance R7).
final class PushSchedulerCopyTests: PushSchedulerTestCase {
    /// The cache as it was under older copy rules: every key changed, so
    /// none matches any more.
    private func ageCache() throws {
        let file = folder.appendingPathComponent("ai-cache.json")
        let data = try Data(contentsOf: file)
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let aged = Dictionary(uniqueKeysWithValues: entries.map { ("v1-" + $0.key, $0.value) })
        try JSONSerialization.data(withJSONObject: aged).write(to: file)
    }

    /// The first return after the copy rules change takes back the pushes
    /// written under the old ones and composes them again, once -- even
    /// within the hour the gate would hold.
    func testNewCopyRulesComposeTheScheduledPushesAgainOnce() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        XCTAssertEqual(state.load().copyVersion, TriggerMemory.copyVersion, "a first launch has nothing to redo")
        let before = active
        XCTAssertEqual(before.count, 7)
        XCTAssertEqual(client.submitted.count, 7)
        try ageCache()
        try state.update { $0.copyVersion = nil }

        clock.advance(600)
        await scheduler.appBecameActive()
        XCTAssertEqual(log.runs().first?.trigger, "copyUpgrade")
        XCTAssertEqual(client.submitted.count, 14, "old words never reused: every night asked again")
        let old = Set(before.map(\.pushId))
        let taken = ledger.load().filter { old.contains($0.pushId) }
        XCTAssertTrue(taken.allSatisfy { $0.removedReason == .copyUpgrade })
        XCTAssertEqual(active.count, 7)
        XCTAssertTrue(Set(active.map(\.pushId)).isDisjoint(with: old))
        XCTAssertEqual(state.load().copyVersion, TriggerMemory.copyVersion)

        clock.advance(600)
        await scheduler.appBecameActive()
        XCTAssertEqual(client.submitted.count, 14, "once only")
        XCTAssertEqual(ledger.load().filter { $0.removedReason == .copyUpgrade }.count, 7)
    }

    /// A push due within the hour stays as it is.
    func testCopyUpgradeKeepsALockedPush() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        try state.update { $0.copyVersion = "copy_v1" }
        clock.now = tonight.scheduledFor.addingTimeInterval(-1800)
        await scheduler.appBecameActive()
        XCTAssertNil(ledger.load().first { $0.pushId == tonight.pushId }?.removedReason)
        XCTAssertEqual(ledger.load().filter { $0.removedReason == .copyUpgrade }.count, 6)
    }
}

/// The scheduler composing the fake AI's pushes again with the real AI
/// once the switch is off. `fake` is read when a scheduler is made, so the
/// switch turned off is a second scheduler on the same stores.
final class PushSchedulerFakeAIOffTests: PushSchedulerTestCase {
    /// Seven nights scheduled by the fake AI; their push ids.
    private func scheduleWithFakeAI() async throws -> Set<String> {
        fake = true
        await makeScheduler().appBecameActive()
        XCTAssertEqual(active.count, 7)
        XCTAssertTrue(client.submitted.isEmpty)
        XCTAssertTrue(try active.allSatisfy { try XCTUnwrap(records.load($0.pushId)).memory.isFakeMade })
        fake = false
        return Set(active.map(\.pushId))
    }

    /// Every night composed again with the real AI.
    private func assertComposedAgain(_ old: Set<String>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(log.runs().first?.trigger, "fakeAIOff", file: file, line: line)
        XCTAssertEqual(client.submitted.count, 7, "every night asked of the backend", file: file, line: line)
        let taken = ledger.load().filter { old.contains($0.pushId) }
        XCTAssertTrue(taken.allSatisfy { $0.removedReason == .fakeAIOff }, file: file, line: line)
        XCTAssertEqual(activeDays, allSeven, file: file, line: line)
        XCTAssertTrue(Set(active.map(\.pushId)).isDisjoint(with: old), file: file, line: line)
        XCTAssertFalse(active.contains { records.load($0.pushId)?.memory.isFakeMade ?? true }, file: file, line: line)
    }

    /// The first return with the switch off takes back the fake AI's pushes
    /// and composes them again -- even within the hour the gate would hold.
    func testReturnWithFakeAIOffComposesItsPushesAgain() async throws {
        let old = try await scheduleWithFakeAI()
        let scheduler = makeScheduler()
        clock.advance(600)
        await scheduler.appBecameActive()
        assertComposedAgain(old)

        clock.advance(600)
        await scheduler.appBecameActive()
        XCTAssertEqual(client.submitted.count, 7, "nothing fake left: the gate holds again")
    }

    /// Turned off with the app open: the same, at once.
    func testSwitchTurnedOffComposesItsPushesAgain() async throws {
        let old = try await scheduleWithFakeAI()
        clock.advance(600)
        await makeScheduler().fakeAITurnedOff()
        assertComposedAgain(old)
    }

    /// With the switch still on, nothing is taken back.
    func testFakeAIOnKeepsItsPushes() async throws {
        let old = try await scheduleWithFakeAI()
        fake = true
        let scheduler = makeScheduler()
        await scheduler.fakeAITurnedOff()
        clock.advance(600)
        await scheduler.appBecameActive()
        XCTAssertEqual(Set(active.map(\.pushId)), old)
        XCTAssertFalse(ledger.load().contains { $0.removedReason == .fakeAIOff })
    }

    /// A push due within the hour stays as it is; debug pushes are never
    /// touched.
    func testFakeAIOffKeepsALockedPushAndDebugPushes() async throws {
        let old = try await scheduleWithFakeAI()
        let tonight = try XCTUnwrap(active.first)
        let scheduler = makeScheduler()
        _ = await scheduler.previewNext()
        let debug = try XCTUnwrap(ledger.load().first(where: \.isDebug))
        XCTAssertTrue(try XCTUnwrap(records.load(debug.pushId)).memory.isFakeMade)
        clock.now = tonight.scheduledFor.addingTimeInterval(-1800)
        await scheduler.appBecameActive()
        XCTAssertEqual(log.runs().first?.trigger, "fakeAIOff")
        XCTAssertNil(ledger.load().first { $0.pushId == tonight.pushId }?.removedReason)
        XCTAssertEqual(ledger.load().filter { $0.removedReason == .fakeAIOff }.map(\.pushId).count, 6)
        XCTAssertTrue(ledger.load().filter { $0.removedReason == .fakeAIOff }.allSatisfy { old.contains($0.pushId) })
        XCTAssertNotEqual(ledger.load().first { $0.pushId == debug.pushId }?.removedReason, .fakeAIOff)
        XCTAssertFalse(notifier.removedPending.contains(debug.identifier))
        XCTAssertNotNil(records.load(debug.pushId))
    }

    /// Killed after the take-back, before the run ended: the next return
    /// still runs, within the hour.
    func testKilledMidRunStillRunsOnTheNextReturn() async throws {
        _ = try await scheduleWithFakeAI()
        let taken = await makeScheduler().takeBackFakeCopy()
        XCTAssertTrue(taken)
        XCTAssertTrue(active.isEmpty)
        XCTAssertTrue(state.load().lastRunLeftDaysUnfilled)
        clock.advance(600)
        await makeScheduler().appBecameActive()
        XCTAssertEqual(log.runs().first?.trigger, "foreground")
        XCTAssertEqual(activeDays, allSeven)
        XCTAssertEqual(client.submitted.count, 7)
    }

    /// The switch turned off while a fake-AI run schedules its nights (the
    /// third night's notification being added): no fake push is left, and
    /// every night is composed by the backend.
    func testSwitchOffMidRunLeavesNoFakePush() async throws {
        try await switchOffMidRun(atSchedule: 3)
    }

    /// The same before any fake push reached the ledger: there is nothing
    /// to take back yet, and still the run that follows composes them all.
    func testSwitchOffBeforeTheFirstFakePushLandsLeavesNone() async throws {
        try await switchOffMidRun(atSchedule: 1)
    }

    private func switchOffMidRun(atSchedule number: Int, file: StaticString = #filePath,
                                 line: UInt = #line) async throws {
        let flag = FlagBox(true)
        let scheduler = makeScheduler(fakeAI: flag)
        let calls = CallCounter()
        notifier.onSchedule = {
            guard calls.bump() == number else { return }
            flag.value = false
            await scheduler.fakeAITurnedOff()
        }
        await scheduler.appBecameActive()
        notifier.onSchedule = nil
        XCTAssertEqual(log.runs().first?.trigger, "fakeAIOff", file: file, line: line)
        XCTAssertFalse(active.contains { records.load($0.pushId)?.memory.isFakeMade ?? true }, "no fake copy left",
                       file: file, line: line)
        XCTAssertEqual(activeDays, allSeven, file: file, line: line)
        let ours = notifier.pendingIds.filter(PushIdentifier.isOurs)
        XCTAssertEqual(ours, Set(active.map(\.identifier)), "no fake request left pending", file: file, line: line)
    }

    /// An older build cached the fake AI's words: a real run asks the
    /// backend anyway, and its answers replace them.
    func testFakeWordsInTheCacheAreNotReused() async throws {
        _ = try await scheduleWithFakeAI()
        for entry in active {
            let record = try XCTUnwrap(records.load(entry.pushId))
            try cache.store(.ok(memory: record.memory, photoIds: record.photoIds),
                            key: AIResultCache.key(Array(record.photoIds.values)), belongsTo: entry.belongsTo,
                            at: clock.now)
        }
        let key = AIResultCache.key((0..<9).map { "g0-\($0)" })
        let stored = try Data(contentsOf: folder.appendingPathComponent("ai-cache.json"))
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: stored) as? [String: Any]).keys
        XCTAssertTrue(keys.contains(key), "planted where the run looks")
        XCTAssertTrue(cache.verdicts().isEmpty)
        await makeScheduler().replan()
        XCTAssertEqual(client.submitted.count, 7, "the fake words are not reused")
        guard case .ok(let memory, _) = cache.verdict(key) else { return XCTFail("the backend's answer is cached") }
        XCTAssertFalse(memory.isFakeMade)
    }
}
