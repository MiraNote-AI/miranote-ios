import XCTest
@testable import MiraNoteKit

// The scheduler around what has already happened: pushes that fired,
// time-zone changes, and a request the app was killed in the middle of.

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
