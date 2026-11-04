import XCTest
@testable import MiraNoteKit

/// The story's "..." menu and what the user did with a push.
final class PushSchedulerMenuTests: PushSchedulerTestCase {
    /// One more food group past the seven, for refills.
    private func addSpare(_ prefix: String = "g7", daysAgo: Double = 10) {
        library.add(prefix, start: start.addingTimeInterval(-daysAgo * 86_400 - 6 * 3600), count: 3)
    }

    func testMenuDayCancelsAndRefills() async throws {
        addSpare()
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let target = try XCTUnwrap(active.first { $0.belongsTo == day("g2") })
        await scheduler.menu(.notThisDay, pushId: target.pushId)
        let entry = try XCTUnwrap(ledger.load().first { $0.pushId == target.pushId })
        XCTAssertEqual(entry.removedReason, .menuDay)
        XCTAssertEqual(entry.menuAction, .notThisDay)
        XCTAssertNotNil(entry.menuActionAt)
        XCTAssertTrue(notifier.removedPending.contains(target.identifier))
        XCTAssertNotNil(preferences.load().blockedDays[day("g2")])
        XCTAssertFalse(activeDays.contains(day("g2")))
        XCTAssertEqual(active.count, 7, "the gap is filled at once")
        XCTAssertTrue(activeDays.contains(day("g7")))
        XCTAssertEqual(log.runs().first?.trigger, "menu")
    }

    func testMenuBucketCancelsAndRefills() async throws {
        analyzer.labels = ["g2": "animal", "g4": "animal"]
        addSpare()
        addSpare("g8", daysAgo: 11)
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let animals = active.filter { $0.bucket == .animal }
        XCTAssertEqual(animals.count, 2)
        await scheduler.menu(.fewerLikeThis, pushId: animals[0].pushId)
        let entries = ledger.load()
        for animal in animals {
            XCTAssertEqual(entries.first { $0.pushId == animal.pushId }?.removedReason, .menuBucket)
        }
        XCTAssertNotNil(preferences.load().fewer[.animal])
        XCTAssertFalse(active.contains { $0.bucket == .animal }, "the bucket cools down for 30 days")
        XCTAssertEqual(active.count, 7)
    }

    /// A record saved before phase 2: no ledger row, no bucket id, no
    /// belongs-to day -- only the memory's own date.
    private func saveOldRecord(date: String) throws -> String {
        let base = TriggerMemoryTests.memory(ids: ["P1", "P2", "P3"], peak: "P2")
        let memory = TriggerMemory(id: "old", date: date, daypart: base.daypart, push: base.push, story: base.story,
                                   ending: base.ending)
        let record = PushRecord(pushId: "old-push", memory: memory, photoIds: [:], createdAt: start, rank: 1,
                                score: 0.5, bucket: "food")
        try records.save(record)
        return record.pushId
    }

    func testMenuDayOnAnOldRecordUsesTheMemoryDate() async throws {
        addSpare()
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        XCTAssertTrue(activeDays.contains(day("g2")))
        let pushId = try saveOldRecord(date: day("g2"))
        await scheduler.menu(.notThisDay, pushId: pushId)
        XCTAssertNotNil(preferences.load().blockedDays[day("g2")], "the memory's day is blocked")
        XCTAssertFalse(activeDays.contains(day("g2")), "its scheduled push is taken back")
        XCTAssertEqual(active.count, 7, "and the night refilled")
    }

    func testMenuFewerOnAnOldRecordDoesNothing() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let before = active
        let pushId = try saveOldRecord(date: day("g2"))
        await scheduler.menu(.fewerLikeThis, pushId: pushId)
        XCTAssertTrue(preferences.load().fewer.isEmpty, "no bucket to cool down")
        XCTAssertEqual(active, before)
    }

    func testMenuDayOnAnOldRecordWithABadDateDoesNothing() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let pushId = try saveOldRecord(date: "Nov 1")
        await scheduler.menu(.notThisDay, pushId: pushId)
        XCTAssertTrue(preferences.load().blockedDays.isEmpty)
    }

    func testMenuFromDebugPushStillApplies() async throws {
        addSpare()
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        let preview = await scheduler.previewNext()
        XCTAssertEqual(preview, .scheduled(slotDay: "2025-10-31"))
        let debug = try XCTUnwrap(ledger.load().first(where: \.isDebug))
        await scheduler.menu(.notThisDay, pushId: debug.pushId)
        XCTAssertNotNil(preferences.load().blockedDays[tonight.belongsTo])
        XCTAssertEqual(ledger.load().first { $0.pushId == tonight.pushId }?.removedReason, .menuDay)
        XCTAssertEqual(ledger.load().first { $0.pushId == debug.pushId }?.menuAction, .notThisDay)
        XCTAssertFalse(activeDays.contains(tonight.belongsTo))
    }

    func testFewerLikeThisIsIgnoredForOther() async throws {
        analyzer.labels = ["g0": "art"]
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let other = try XCTUnwrap(active.first { $0.bucket == .other })
        await scheduler.menu(.fewerLikeThis, pushId: other.pushId)
        XCTAssertEqual(preferences.load(), PushPreferences())
        XCTAssertTrue(active.contains(other))
        XCTAssertEqual(log.runs().count, 1)
    }

    /// E6: opening, finishing and making a page only go in the ledger.
    func testNoAutomaticLearning() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        clock.now = tonight.scheduledFor.addingTimeInterval(120)
        await scheduler.markOpened(tonight.pushId)
        await scheduler.markStoryFinished(tonight.pushId)
        await scheduler.markMadePage(tonight.pushId)
        let second = try XCTUnwrap(active.first)
        clock.now = second.scheduledFor.addingTimeInterval(LedgerReconciler.openWindow + 60)
        notifier.pendingIds = []
        await scheduler.appBecameActive()
        XCTAssertEqual(preferences.load(), PushPreferences())
        XCTAssertTrue(ledger.load().contains(where: \.notOpened), "skipped: only the ledger knows")
        XCTAssertTrue(active.allSatisfy { $0.score.multiplier == 1.0 })
        let entry = try XCTUnwrap(ledger.load().first { $0.pushId == tonight.pushId })
        XCTAssertNotNil(entry.openedAt)
        XCTAssertNotNil(entry.storyFinishedAt)
        XCTAssertNotNil(entry.madePageAt)
    }

    func testDeliveredUnopenedAfterTwoDaysIsCleared() async throws {
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        let tonight = try XCTUnwrap(active.first)
        clock.now = tonight.scheduledFor.addingTimeInterval(LedgerReconciler.openWindow + 60)
        notifier.pendingIds.remove(tonight.identifier)
        await scheduler.appBecameActive()
        XCTAssertTrue(notifier.removedDelivered.contains(tonight.identifier))
        let entry = try XCTUnwrap(ledger.load().first { $0.pushId == tonight.pushId })
        XCTAssertEqual(entry.deliveredAt, tonight.scheduledFor)
        XCTAssertTrue(entry.notOpened)
    }
}
