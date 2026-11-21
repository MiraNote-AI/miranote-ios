import XCTest
@testable import MiraNoteKit

final class RepeatLedgerTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    /// A ledger row exactly as the encoder wrote it before push modes existed.
    private let oldRow = """
    {"belongsTo":"2026-10-30","body":"Body","bucket":"scenery","groupKey":"g-A","identifier":"pt.A",\
    "isDebug":false,"notOpened":false,"photoIds":["LOCAL-1\\/L0\\/001","LOCAL-2\\/L0\\/001"],\
    "place":"Arboretum","pushId":"A","question":"What else?","questionType":"zoom",\
    "scheduledFor":"2027-01-15T08:00:00Z","score":{"a":0.6,"base":0.55,"bucket":"scenery","days":2,\
    "multiplier":1,"n":0.4,"p":0.2,"pushable":true,"r":1,"s":0.5,"total":0.55,"u":0}}
    """

    private func repeatEntry() -> LedgerEntry {
        var entry = PushLedgerTests.entry("R", at: at, debug: true)
        entry.mode = "repeat"
        entry.themeId = "0123456789abcdef-theme"
        entry.themeName = "Dinner at home"
        entry.roundUsages = [
            RoundUsage(promptTokens: 1000, completionTokens: 200, costCny: 0.01234, model: "qwen-vl"),
            RoundUsage(promptTokens: 500, completionTokens: 100, costCny: 0.00566, model: "qwen-vl")
        ]
        entry.roundTwoTries = ["too_few_photos"]
        return entry
    }

    func testOldLedgerWithoutModeDecodesAsLifeFragment() throws {
        let entry = try TriggerMemory.decoder.decode(LedgerEntry.self, from: Data(oldRow.utf8))
        XCTAssertEqual(entry.mode, "life_fragment")
        XCTAssertNil(entry.themeId)
        XCTAssertNil(entry.themeName)
        XCTAssertNil(entry.roundUsages)
        XCTAssertNil(entry.roundTwoTries)
        XCTAssertEqual(entry.pushId, "A")
        XCTAssertEqual(entry.photoIds.count, 2)
    }

    func testNewLifeFragmentRowDecodesAsLifeFragment() throws {
        let entry = PushLedgerTests.entry(at: at)
        XCTAssertEqual(entry.mode, "life_fragment")
        let back = try TriggerMemory.decoder.decode(LedgerEntry.self, from: TriggerMemory.encoder.encode(entry))
        XCTAssertEqual(back, entry)
    }

    func testRepeatDebugRowRoundTrips() throws {
        let entry = repeatEntry()
        let data = try TriggerMemory.encoder.encode(entry)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["mode"] as? String, "repeat")
        let back = try TriggerMemory.decoder.decode(LedgerEntry.self, from: data)
        XCTAssertEqual(back, entry)
        XCTAssertEqual(back.roundUsages?.count, 2)
        XCTAssertEqual(back.roundTwoTries, ["too_few_photos"])
    }

    func testPushRecordCarriesTheModeAndOldRecordsStillDecode() throws {
        let memory = TriggerMemoryTests.memory(ids: ["P1", "P2", "P3"], peak: "P1")
        let plain = PushRecord(pushId: "A", memory: memory, photoIds: ["P1": "L1"], createdAt: at, rank: 1,
                               score: 0.5, bucket: "b")
        let plainData = try TriggerMemory.encoder.encode(plain)
        let plainKeys = try XCTUnwrap(try JSONSerialization.jsonObject(with: plainData) as? [String: Any])
        XCTAssertNil(plainKeys["mode"])
        XCTAssertNil(try TriggerMemory.decoder.decode(PushRecord.self, from: plainData).mode)
        let usage = [RoundUsage(promptTokens: 1, completionTokens: 2, costCny: 0.5, model: "m")]
        let record = PushRecord(pushId: "R", memory: memory, photoIds: ["P1": "L1"],
                                createdAt: at, rank: 1, score: 0.5, bucket: "b", mode: "repeat",
                                themeId: "t1", themeName: "Name", roundUsages: usage, roundTwoTries: ["x"])
        let back = try TriggerMemory.decoder.decode(PushRecord.self, from: TriggerMemory.encoder.encode(record))
        XCTAssertEqual(back, record)
        XCTAssertEqual(back.mode, "repeat")
    }

    func testCopiedLedgerHasThemeAndNoCoordinates() {
        let text = LedgerText.copy(entries: [repeatEntry(), PushLedgerTests.entry("B", at: at)], runs: [],
                                   counters: ScheduleCounters())
        XCTAssertTrue(text.contains("repeat | Dinner at home | 01234567"))
        XCTAssertFalse(text.contains("0123456789"))
        XCTAssertTrue(text.contains("cost 0.0180"))
        XCTAssertTrue(text.contains("tokens 1500/300"))
        XCTAssertTrue(text.contains("round 2 tries: too_few_photos"))
        XCTAssertFalse(text.contains("LOCAL-"))
        XCTAssertFalse(text.contains("g-R"))
        XCTAssertFalse(text.lowercased().contains("latitude"))
    }
}
