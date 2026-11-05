import XCTest
@testable import MiraNoteKit

final class PushPreferencesTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("preferences.json")
    }

    func testFewerBlocksThirtyDaysThenPointSix() {
        let prefs = PushPreferences(fewer: [.food: base])
        XCTAssertNil(prefs.multiplier(for: .food, at: base.addingTimeInterval(29.9 * 86_400)))
        XCTAssertEqual(prefs.multiplier(for: .food, at: base.addingTimeInterval(30 * 86_400)), 0.6)
        XCTAssertEqual(prefs.multiplier(for: .city, at: base), 1.0)
    }

    func testClearedBucketIsBackToOne() {
        var prefs = PushPreferences(fewer: [.food: base])
        prefs.fewer[.food] = nil
        XCTAssertEqual(prefs.multiplier(for: .food, at: base), 1.0)
    }

    func testBlockedDay() {
        let prefs = PushPreferences(blockedDays: ["2026-10-30": base])
        XCTAssertTrue(prefs.isBlocked("2026-10-30"))
        XCTAssertFalse(prefs.isBlocked("2026-10-31"))
    }

    func testBlockedPhotos() {
        let prefs = PushPreferences(blockedDays: ["2026-10-30": base], blockedPhotos: ["2026-10-30": ["a", "b"]])
        XCTAssertTrue(prefs.isBlocked("2026-10-29", photoIds: ["z", "b"]), "the same photos, another day key")
        XCTAssertTrue(prefs.isBlocked("2026-10-30", photoIds: []))
        XCTAssertFalse(prefs.isBlocked("2026-10-29", photoIds: ["z"]))
    }

    /// A file written before blocked photos: its days still block.
    func testPreferencesFromBeforeBlockedPhotosLoad() throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"blockedDays":{"2026-10-30":"2026-10-31T00:00:00Z"},"fewer":{}}"#.utf8).write(to: file)
        let loaded = PushPreferencesStore(file: file).load()
        XCTAssertTrue(loaded.isBlocked("2026-10-30"))
        XCTAssertEqual(loaded.blockedPhotos, [:])
    }

    func testOtherIsNeverReduced() {
        let prefs = PushPreferences(fewer: [.other: base])
        XCTAssertEqual(prefs.multiplier(for: .other, at: base), 1.0)
    }

    func testPreferencesLoadEmptyFromGarbage() throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json {".utf8).write(to: file)
        XCTAssertEqual(PushPreferencesStore(file: file).load(), PushPreferences())
        XCTAssertEqual(PushPreferencesStore(file: tempFile()).load(), PushPreferences())
    }

    func testRoundTripAndUpdate() throws {
        let store = PushPreferencesStore(file: tempFile())
        try store.update { $0.blockedDays["2026-10-30"] = base }
        try store.update { $0.fewer[.scenery] = base }
        let loaded = store.load()
        XCTAssertEqual(loaded.blockedDays["2026-10-30"], base)
        XCTAssertEqual(loaded.fewer[.scenery], base)
    }
}
