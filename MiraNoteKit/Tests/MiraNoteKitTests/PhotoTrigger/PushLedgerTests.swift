import XCTest
@testable import MiraNoteKit

final class PushLedgerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("ledger.json")
    }

    static func score() -> FragmentScore {
        FragmentScore(r: 1, s: 0.5, p: 0.2, n: 0.4, u: 0, a: 0.6, base: 0.55, multiplier: 1, bucket: .scenery,
                      total: 0.55, days: 2, pushable: true)
    }

    static func entry(_ id: String = "A", day: String = "2026-10-30", at: Date, debug: Bool = false) -> LedgerEntry {
        LedgerEntry(pushId: id, isDebug: debug, belongsTo: day, groupKey: "g-\(id)",
                    photoIds: ["LOCAL-1/L0/001", "LOCAL-2/L0/001"], bucket: .scenery, place: "Arboretum",
                    score: score(), body: "Body", question: "What else?", questionType: "zoom",
                    scheduledFor: at)
    }

    private func reconcile(_ entries: [LedgerEntry], pending: Set<String> = [], allowed: Bool = true) -> [LedgerEntry] {
        LedgerReconciler.reconcile(entries, now: now, pending: pending, notificationsAllowed: allowed).entries
    }

    func testDueAndNotPendingIsDelivered() {
        let due = now.addingTimeInterval(-3600)
        let out = reconcile([Self.entry(at: due)])
        XCTAssertEqual(out[0].deliveredAt, due)
        XCTAssertEqual(out[0].identifier, "pt.A")
        let still = reconcile([Self.entry(at: due)], pending: ["pt.A"])
        XCTAssertNil(still[0].deliveredAt)
    }

    func testNotYetDueIsNotPushed() {
        let out = reconcile([Self.entry(at: now.addingTimeInterval(3600))])
        XCTAssertNil(out[0].deliveredAt)
        XCTAssertTrue(LedgerReconciler.pushedDays(out).isEmpty)
        XCTAssertTrue(out[0].isActive)
    }

    func testDebugPushIsNeverAPushedDay() {
        let out = reconcile([Self.entry(at: now.addingTimeInterval(-60), debug: true)])
        XCTAssertNotNil(out[0].deliveredAt)
        XCTAssertTrue(LedgerReconciler.pushedDays(out).isEmpty)
    }

    func testReconcileWithNotificationsOffDoesNotCountAsPushed() {
        let out = reconcile([Self.entry(at: now.addingTimeInterval(-60))], allowed: false)
        XCTAssertNil(out[0].deliveredAt)
        XCTAssertEqual(out[0].notDeliveredReason, "notificationsOff")
        XCTAssertTrue(LedgerReconciler.pushedDays(out).isEmpty)
        XCTAssertFalse(out[0].isActive, "dropped by iOS: it no longer holds its group or day")
    }

    func testNotificationsOffReasonIsTerminal() {
        let first = reconcile([Self.entry(at: now.addingTimeInterval(-60))], allowed: false)
        let second = reconcile(first, allowed: true)
        XCTAssertNil(second[0].deliveredAt)
        XCTAssertEqual(second[0].notDeliveredReason, "notificationsOff")
        XCTAssertTrue(LedgerReconciler.pushedDays(second).isEmpty)
    }

    func testAlreadyFlaggedNotOpenedIsNotClearedAgain() {
        var old = Self.entry(at: now.addingTimeInterval(-200_000))
        old.deliveredAt = old.scheduledFor
        let first = LedgerReconciler.reconcile([old], now: now, pending: [], notificationsAllowed: true)
        XCTAssertEqual(first.clearDelivered, ["pt.A"])
        let second = LedgerReconciler.reconcile(first.entries, now: now, pending: [], notificationsAllowed: true)
        XCTAssertTrue(second.clearDelivered.isEmpty)
    }

    func testNotOpenedAfterFortyEightHours() {
        var old = Self.entry(at: now.addingTimeInterval(-172_800))
        old.deliveredAt = old.scheduledFor
        var young = Self.entry("B", at: now.addingTimeInterval(-172_000))
        young.deliveredAt = young.scheduledFor
        let result = LedgerReconciler.reconcile([old, young], now: now, pending: [], notificationsAllowed: true)
        XCTAssertTrue(result.entries[0].notOpened)
        XCTAssertFalse(result.entries[1].notOpened)
    }

    func testClearsOnlyDeliveredUnopenedOlderThanTwoDays() {
        var oldUnopened = Self.entry("A", at: now.addingTimeInterval(-200_000))
        oldUnopened.deliveredAt = oldUnopened.scheduledFor
        var oldOpened = Self.entry("B", at: now.addingTimeInterval(-200_000))
        oldOpened.deliveredAt = oldOpened.scheduledFor
        oldOpened.openedAt = oldOpened.scheduledFor
        var youngUnopened = Self.entry("C", at: now.addingTimeInterval(-3600))
        youngUnopened.deliveredAt = youngUnopened.scheduledFor
        let waiting = Self.entry("D", at: now.addingTimeInterval(3600))
        let result = LedgerReconciler.reconcile([oldUnopened, oldOpened, youngUnopened, waiting], now: now,
                                                pending: ["pt.D"], notificationsAllowed: true)
        XCTAssertEqual(result.clearDelivered, ["pt.A"])
    }

    func testRemovedEntryIsNotDelivered() {
        var removed = Self.entry(at: now.addingTimeInterval(-60))
        removed.removedReason = .replaced
        removed.removedAt = now.addingTimeInterval(-600)
        let out = reconcile([removed])
        XCTAssertNil(out[0].deliveredAt)
        XCTAssertFalse(out[0].isActive)
    }

    func testExportIsJSONOfEveryField() throws {
        var entry = Self.entry(at: now)
        entry.menuAction = .fewerLikeThis
        entry.removedReason = .menuBucket
        let store = PushLedgerStore(file: tempFile())
        try store.append(entry)
        let data = try store.exportJSON()
        let text = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\n"))
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let keys = Set(try XCTUnwrap(array.first).keys)
        for key in ["pushId", "identifier", "isDebug", "belongsTo", "groupKey", "photoIds", "bucket", "place",
                    "score", "body", "question", "questionType", "scheduledFor", "notOpened", "menuAction",
                    "removedReason"] {
            XCTAssertTrue(keys.contains(key), key)
        }
        XCTAssertTrue(text.contains("2027-01-15T08:00:00Z"))
        let back = try TriggerMemory.decoder.decode([LedgerEntry].self, from: data)
        XCTAssertEqual(back, [entry])
    }

    /// A ledger written before question types (`questionId`) still loads:
    /// its rows have no question and no type.
    func testLedgerFromBeforeQuestionTypesLoads() throws {
        let data = try TriggerMemory.encoder.encode([Self.entry(at: now)])
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        rows[0]["question"] = nil
        rows[0]["questionType"] = nil
        rows[0]["questionId"] = "A1"
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: rows).write(to: file)
        let loaded = PushLedgerStore(file: file).load()
        XCTAssertEqual(loaded.map(\.pushId), ["A"])
        XCTAssertNil(loaded.first?.question)
        XCTAssertNil(loaded.first?.questionType)
    }

    func testLedgerLoadsEmptyFromGarbage() throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[{ nope".utf8).write(to: file)
        XCTAssertEqual(PushLedgerStore(file: file).load(), [])
        XCTAssertEqual(PushLedgerStore(file: tempFile()).load(), [])
    }

    /// The files next to `file` it was set aside as.
    static func setAside(_ file: URL) throws -> [URL] {
        let folder = file.deletingLastPathComponent()
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(file.lastPathComponent + ".corrupt-") }
    }

    /// A row this build cannot read (a newer build's removal reason) costs
    /// that row, not the history: the rest loads, and the file as it was
    /// is kept aside before anything is written.
    func testOneBadRowCostsThatRowOnly() throws {
        let file = tempFile()
        let store = PushLedgerStore(file: file)
        try store.save([Self.entry("A", at: now), Self.entry("B", at: now)])
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        rows[1]["removedReason"] = "someFutureReason"
        let damaged = try JSONSerialization.data(withJSONObject: rows)
        try damaged.write(to: file)
        XCTAssertEqual(store.load().map(\.pushId), ["A"])
        try store.append(Self.entry("C", at: now))
        XCTAssertEqual(store.load().map(\.pushId), ["A", "C"])
        let aside = try XCTUnwrap(Self.setAside(file).first)
        XCTAssertEqual(try Data(contentsOf: aside), damaged)
    }

    /// A file that does not parse at all is moved aside, never written over.
    func testUnparsableLedgerIsSetAsideNotOverwritten() throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[{ nope".utf8).write(to: file)
        let store = PushLedgerStore(file: file)
        try store.append(Self.entry("A", at: now))
        XCTAssertEqual(store.load().map(\.pushId), ["A"])
        let aside = try Self.setAside(file)
        XCTAssertEqual(aside.count, 1)
        XCTAssertEqual(try aside.first.map { try Data(contentsOf: $0) }, Data("[{ nope".utf8))
    }

    func testStoreIsExcludedFromBackup() throws {
        let file = tempFile()
        try PushLedgerStore(file: file).append(Self.entry(at: now))
        let values = try file.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testUpdateChangesOneEntry() throws {
        let store = PushLedgerStore(file: tempFile())
        try store.append(Self.entry("A", at: now))
        try store.append(Self.entry("B", at: now))
        try store.update("B") { $0.openedAt = self.now }
        XCTAssertNil(store.load()[0].openedAt)
        XCTAssertEqual(store.load()[1].openedAt, now)
    }
}
