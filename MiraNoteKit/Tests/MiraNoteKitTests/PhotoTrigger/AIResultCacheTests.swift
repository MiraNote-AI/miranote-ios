import XCTest
@testable import MiraNoteKit

final class AIResultCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("ai-cache.json")
    }

    private var ok: AIVerdict {
        .ok(memory: TriggerMemoryTests.memory(ids: ["P1", "P2", "P3"], peak: "P1"), photoIds: ["P1": "a", "P2": "b"])
    }

    func testSamePhotosHitDifferentPhotoMisses() throws {
        let cache = AIResultCache(file: tempFile())
        try cache.store(ok, key: AIResultCache.key(["a", "b", "c"]), belongsTo: "2026-10-30", at: now)
        XCTAssertEqual(cache.verdict(AIResultCache.key(["c", "a", "b"])), ok)
        XCTAssertNil(cache.verdict(AIResultCache.key(["a", "b", "d"])))
    }

    /// The same memory as made by the fake AI.
    private var fakeMade: AIVerdict {
        let base = TriggerMemoryTests.memory(ids: ["P1", "P2", "P3"], peak: "P1")
        let memory = TriggerMemory(
            id: base.id, date: base.date, daypart: base.daypart, push: base.push, story: base.story,
            ending: base.ending,
            generation: .init(bodySource: FakeAIMemory.source, questionSource: FakeAIMemory.source,
                              model: "on-device", costCny: 0, latencyMs: 0))
        return .ok(memory: memory, photoIds: ["P1": "a"])
    }

    /// A fake-AI memory an older build stored reads as absent, so the
    /// backend is asked; its answer then takes the key.
    func testFakeMadeMemoryReadsAsAbsent() throws {
        let cache = AIResultCache(file: tempFile())
        try cache.store(fakeMade, key: "fake", belongsTo: "2026-10-30", at: now)
        try cache.store(ok, key: "real", belongsTo: "2026-10-30", at: now)
        XCTAssertNil(cache.verdict("fake"))
        XCTAssertEqual(cache.verdicts(), ["real": ok])
        try cache.store(ok, key: "fake", belongsTo: "2026-10-30", at: now)
        XCTAssertEqual(cache.verdict("fake"), ok)
    }

    func testRejectedIsCached() throws {
        let cache = AIResultCache(file: tempFile())
        let rejected = AIVerdict.rejected(reason: "sensitive", message: "no")
        try cache.store(rejected, key: "k", belongsTo: "2026-10-30", at: now)
        XCTAssertEqual(cache.verdict("k"), rejected)
    }

    /// Words written under other copy rules never come back for the same
    /// photos (handoff refine 5.4, acceptance R7).
    func testKeyChangesWithTheCopyVersion() throws {
        XCTAssertEqual(TriggerMemory.copyVersion, "copy_v2")
        XCTAssertNotEqual(AIResultCache.key(["a", "b"], copyVersion: "copy_v1"), AIResultCache.key(["a", "b"]))
        XCTAssertNotEqual(AIResultCache.key(["a", "b"], copyVersion: ""), AIResultCache.key(["a", "b"]))
        let cache = AIResultCache(file: tempFile())
        try cache.store(ok, key: AIResultCache.key(["a", "b", "c"], copyVersion: ""), belongsTo: "2026-10-30",
                        at: now)
        XCTAssertNil(cache.verdict(AIResultCache.key(["a", "b", "c"])))
    }

    func testKeyIgnoresOrder() {
        XCTAssertEqual(AIResultCache.key(["x", "y"]), AIResultCache.key(["y", "x"]))
        XCTAssertEqual(AIResultCache.key(["x"]).count, 64)
    }

    func testPurgeDropsGroupsOlderThanSixtyDays() throws {
        let cache = AIResultCache(file: tempFile())
        try cache.store(ok, key: "old", belongsTo: "2026-08-31", at: now)
        try cache.store(ok, key: "edge", belongsTo: "2026-09-01", at: now)
        try cache.store(ok, key: "new", belongsTo: "2026-10-30", at: now)
        try cache.purge(today: "2026-10-31")
        XCTAssertNil(cache.verdict("old"))
        XCTAssertNotNil(cache.verdict("edge"))
        XCTAssertNotNil(cache.verdict("new"))
    }

    func testCacheLoadsEmptyFromGarbage() throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{{{".utf8).write(to: file)
        XCTAssertNil(AIResultCache(file: file).verdict("k"))
        XCTAssertNoThrow(try AIResultCache(file: file).purge(today: "2026-10-31"))
    }
}
