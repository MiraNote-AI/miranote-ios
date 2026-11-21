import XCTest
@testable import MiraNoteKit

final class ThemePhotoStoreTests: XCTestCase {
    private var directory: URL!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThemePhotoStoreTests-\(UUID().uuidString)", isDirectory: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: parts)!
    }

    private func photo(_ id: String, at takenAt: Date, raw: [Float] = [3, 4, 0, 12]) -> ThemePhoto {
        ThemePhoto(id: id, takenAt: takenAt, location: GeoPoint(lat: 41.88, lon: -87.63),
                   labels: [LabelScore(id: "food", confidence: 0.75)], aesthetics: 0.5, faces: 1,
                   isTheme: true, print: ThemePhoto.normalized(raw), printRevision: 2)
    }

    private func modified(_ name: String) throws -> Date {
        let url = directory.appendingPathComponent(name)
        return try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    }

    func testRoundTripKeepsVectorBitExact() throws {
        let store = ThemePhotoStore(directory: directory)
        let original = photo("a/b", at: date(2026, 11, 3, 12), raw: [0.1, -0.7, 0.33, 0.9, 0.01])
        try store.upsert([original], calendar: calendar)
        let loaded = try XCTUnwrap(ThemePhotoStore(directory: directory).loadAll()["a/b"])
        XCTAssertEqual(loaded, original)
        XCTAssertEqual(loaded.print, original.print)
        XCTAssertEqual(loaded.vector.map(\.bitPattern), original.vector.map(\.bitPattern))
        XCTAssertEqual(loaded.vector.count, 5)
    }

    func testUpsertWritesOneFilePerLocalMonth() throws {
        let store = ThemePhotoStore(directory: directory)
        try store.upsert([photo("a", at: date(2026, 10, 31, 23, 30)),
                          photo("b", at: date(2026, 11, 1, 0, 30))], calendar: calendar)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(names, ["2026-10.json", "2026-11.json"])
        XCTAssertEqual(Set(store.loadAll().keys), ["a", "b"])
    }

    func testUpsertMovesPhotoWhoseMonthChanged() throws {
        let store = ThemePhotoStore(directory: directory)
        try store.upsert([photo("a", at: date(2026, 10, 5, 12))], calendar: calendar)
        try store.upsert([photo("a", at: date(2026, 11, 5, 12))], calendar: calendar)
        XCTAssertEqual(store.loadAll().count, 1)
        let october = try Data(contentsOf: directory.appendingPathComponent("2026-10.json"))
        let text = try XCTUnwrap(String(bytes: october, encoding: .utf8))
        XCTAssertFalse(text.contains("\"id\":\"a\""))
    }

    func testUpsertWithIndexReadsOnlyMonthsItTouches() throws {
        var store = ThemePhotoStore(directory: directory)
        try store.upsert([photo("a", at: date(2026, 9, 5, 12)), photo("b", at: date(2026, 10, 5, 12))],
                         calendar: calendar)
        var index = store.monthIndex()
        let reads = ReadLog()
        store.onRead = { reads.add($0) }

        try store.upsert([photo("c", at: date(2026, 11, 1, 12))], calendar: calendar, index: &index)
        XCTAssertEqual(reads.count(of: "2026-09.json") + reads.count(of: "2026-10.json"), 0)

        // c (written above) moves to October, a from September to November.
        try store.upsert([photo("c", at: date(2026, 10, 7, 12)), photo("a", at: date(2026, 11, 2, 12))],
                         calendar: calendar, index: &index)
        let loaded = store.loadAll()
        XCTAssertEqual(Set(loaded.keys), ["a", "b", "c"])
        XCTAssertEqual(loaded["c"]?.takenAt, date(2026, 10, 7, 12))
        XCTAssertEqual(loaded["a"]?.takenAt, date(2026, 11, 2, 12))
        let september = try String(bytes: Data(contentsOf: directory.appendingPathComponent("2026-09.json")),
                                   encoding: .utf8)
        XCTAssertFalse(september?.contains("\"id\":\"a\"") ?? true)
        let november = try String(bytes: Data(contentsOf: directory.appendingPathComponent("2026-11.json")),
                                  encoding: .utf8)
        XCTAssertFalse(november?.contains("\"id\":\"c\"") ?? true)
    }

    func testRemoveRewritesOnlyThatMonth() throws {
        let store = ThemePhotoStore(directory: directory)
        try store.upsert([photo("a", at: date(2026, 10, 5, 12)), photo("b", at: date(2026, 11, 5, 12)),
                          photo("c", at: date(2026, 11, 6, 12))], calendar: calendar)
        let octoberBefore = try modified("2026-10.json")
        Thread.sleep(forTimeInterval: 1.1)
        try store.remove(["b"], calendar: calendar)
        XCTAssertEqual(try modified("2026-10.json"), octoberBefore)
        XCTAssertEqual(Set(store.loadAll().keys), ["a", "c"])
    }

    func testPruneKeepsOnlyListedIds() throws {
        let store = ThemePhotoStore(directory: directory)
        try store.upsert([photo("a", at: date(2026, 10, 5, 12)), photo("b", at: date(2026, 11, 5, 12))],
                         calendar: calendar)
        try store.prune(keeping: ["b"])
        XCTAssertEqual(Set(store.loadAll().keys), ["b"])
    }

    func testFailuresRoundTripAndPruneWithThePhotos() throws {
        let store = ThemePhotoStore(directory: directory)
        XCTAssertEqual(store.failures(), [:])
        let failed = date(2026, 11, 3, 12)
        try store.saveFailures(["a": failed, "b": failed])
        try store.upsert([photo("c", at: date(2026, 10, 5, 12))], calendar: calendar)
        XCTAssertEqual(store.failures(), ["a": failed, "b": failed])
        XCTAssertEqual(Set(store.loadAll().keys), ["c"], "the failures file is no month")
        try store.prune(keeping: ["b", "c"])
        XCTAssertEqual(store.failures(), ["b": failed])
    }

    func testGarbageMonthLoadsEmptyAndOthersLoad() throws {
        let store = ThemePhotoStore(directory: directory)
        try store.upsert([photo("a", at: date(2026, 10, 5, 12)), photo("b", at: date(2026, 11, 5, 12))],
                         calendar: calendar)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("2026-10.json"))
        XCTAssertEqual(Set(store.loadAll().keys), ["b"])
        try store.upsert([photo("c", at: date(2026, 10, 6, 12))], calendar: calendar)
        XCTAssertEqual(Set(store.loadAll().keys), ["b", "c"])
    }

    func testBadRowCostsOnlyThatRow() throws {
        let store = ThemePhotoStore(directory: directory)
        try store.upsert([photo("a", at: date(2026, 10, 5, 12))], calendar: calendar)
        let url = directory.appendingPathComponent("2026-10.json")
        var text = try XCTUnwrap(String(bytes: Data(contentsOf: url), encoding: .utf8))
        text = text.replacingOccurrences(of: "\"photos\":[", with: "\"photos\":[{\"id\":5},")
        try Data(text.utf8).write(to: url)
        XCTAssertEqual(Set(store.loadAll().keys), ["a"])
    }

    func testNormalizedHasUnitLength() {
        let vector = ThemePhoto(id: "x", takenAt: Date(), location: nil, labels: [], aesthetics: nil, faces: 0,
                                isTheme: false, print: ThemePhoto.normalized([3, 4, 0, 12]), printRevision: 1).vector
        XCTAssertEqual(vector.count, 4)
        XCTAssertEqual(vector.map { $0 * $0 }.reduce(0, +), 1, accuracy: 1e-6)
        XCTAssertEqual(ThemePhoto.normalized([0, 0, 0]).count, 12)
    }

    func testFolderExcludedFromBackup() throws {
        let store = ThemePhotoStore(directory: directory)
        try store.upsert([photo("a", at: date(2026, 10, 5, 12))], calendar: calendar)
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
}
