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
