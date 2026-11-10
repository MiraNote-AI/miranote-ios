import XCTest
@testable import MiraNoteKit

final class ScheduleLogTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("log.json")
    }

    private func run(_ index: Int) -> ScheduleRun {
        let start = base.addingTimeInterval(Double(index) * 60)
        return ScheduleRun(startedAt: start, finishedAt: start.addingTimeInterval(5), trigger: "foreground",
                           fragments: index)
    }

    func testLogKeepsTwenty() throws {
        let store = ScheduleLogStore(file: tempFile())
        for index in 0..<25 { try store.append(run(index)) }
        let runs = store.runs()
        XCTAssertEqual(runs.count, 20)
        XCTAssertEqual(runs.first?.fragments, 24)
        XCTAssertEqual(runs.last?.fragments, 5)
    }

    /// Runs logged before question clashes were kept still load; the
    /// clashes a run noted come back.
    func testQuestionClashesPersistAndOldRunsLoad() throws {
        let file = tempFile()
        var noted = run(1)
        noted.questionClashes = [.init(slotDay: "2026-11-06", types: ["order", "sound"], nearby: ["sound", "order"])]
        try ScheduleLogStore(file: file).append(noted)
        XCTAssertEqual(ScheduleLogStore(file: file).runs(), [noted])

        let data = try TriggerMemory.encoder.encode([run(2)])
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        rows[0]["questionClashes"] = nil
        let old = try JSONSerialization.data(withJSONObject: rows)
        let runs = try TriggerMemory.decoder.decode([ScheduleRun].self, from: old)
        XCTAssertEqual(runs.first?.questionClashes, [])
        XCTAssertEqual(runs.first?.fragments, 2)
    }

    func testCountersPersist() throws {
        let file = tempFile()
        try ScheduleLogStore(file: file).bumpLeftBeforeResult(by: 2)
        try ScheduleLogStore(file: file).bumpLeftBeforeResult(by: 1)
        XCTAssertEqual(ScheduleLogStore(file: file).counters().leftBeforeResult, 3)
        try ScheduleLogStore(file: file).append(run(1))
        XCTAssertEqual(ScheduleLogStore(file: file).counters().leftBeforeResult, 3)
        try ScheduleLogStore(file: file).clear()
        XCTAssertEqual(ScheduleLogStore(file: file).counters().leftBeforeResult, 0)
        XCTAssertTrue(ScheduleLogStore(file: file).runs().isEmpty)
    }

    func testHasError() {
        var value = run(1)
        XCTAssertFalse(value.hasError)
        value.groups = [.init(slotDay: "d", groupKey: "g", belongsTo: "b", outcome: .error, seconds: 1)]
        XCTAssertTrue(value.hasError)
        value.groups = []
        value.error = "x"
        XCTAssertTrue(value.hasError)
    }

    func testLogLoadsEmptyFromGarbage() throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: file)
        XCTAssertTrue(ScheduleLogStore(file: file).runs().isEmpty)
        XCTAssertEqual(ScheduleLogStore(file: file).counters(), ScheduleCounters())
    }

    func testCopiedTextHasNoCoordinatesIdsOrKey() throws {
        var entry = PushLedgerTests.entry(at: base)
        entry.deliveredAt = base
        entry.openedAt = base
        entry.menuAction = .notThisDay
        var value = run(1)
        value.scheduledDays = ["2026-11-05"]
        value.emptyDays = ["2026-11-06": "noCandidate"]
        value.groups = [.init(slotDay: "2026-11-05", groupKey: "g", belongsTo: "2026-10-30", outcome: .error,
                              seconds: 2, message: "timeout")]
        let text = LedgerText.copy(entries: [entry], runs: [value], counters: ScheduleCounters(leftBeforeResult: 1))
        XCTAssertFalse(text.contains("LOCAL-"))
        XCTAssertFalse(text.contains("localIdentifier"))
        XCTAssertNil(text.range(of: #"\d+\.\d{4,}"#, options: .regularExpression))
        XCTAssertTrue(text.contains("Arboretum"))
        XCTAssertTrue(text.contains("scenery"))
        XCTAssertTrue(text.contains("0.55"))
        XCTAssertTrue(text.contains("delivered, opened"))
        XCTAssertTrue(text.contains("notThisDay"))
        XCTAssertTrue(text.contains("timeout"))
        XCTAssertEqual(text.split(separator: "\n").count, 4)
    }

    /// E3: whatever a run carried, the copied text holds no key or token.
    func testCopiedTextHoldsNoSecret() throws {
        let entry = PushLedgerTests.entry(at: base)
        var value = run(1)
        value.error = "Authorization: Bearer abc.def"
        value.groups = [
            .init(slotDay: "2026-11-05", groupKey: "g", belongsTo: "2026-10-30", outcome: .error, seconds: 2,
                  message: "401 token expired, api_key=sk-live-123 apiKey=zz"),
            .init(slotDay: "2026-11-06", groupKey: "h", belongsTo: "2026-10-29", outcome: .error, seconds: 2,
                  message: "timeout")
        ]
        let text = LedgerText.copy(entries: [entry], runs: [value], counters: ScheduleCounters())
        for word in ["bearer", "token", "api_key", "apikey", "sk-"] {
            XCTAssertNil(text.range(of: word, options: .caseInsensitive), word)
        }
        XCTAssertTrue(text.contains("timeout"), "harmless error text stays")
    }
}
