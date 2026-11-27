import Foundation
import XCTest
@testable import MiraNoteKit

// swiftlint:disable:next type_body_length
final class ThemeLibraryTests: XCTestCase {
    private var directory: URL!
    private let facts = WhereFacts(daypart: "evening", daypartShare: 0.8, hourFrom: 18, hourTo: 20,
                                   weekpart: "weekday", places: nil)
    private let place = GeoPoint(lat: 31.2, lon: 121.4)

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThemeLibraryTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Fixtures: moments m1...m6, two photos each (p1a, p1b ...)

    private var moments: [String: Moment] {
        var result: [String: Moment] = [:]
        for index in 1...6 {
            result["m\(index)"] = Moment(id: "m\(index)", photoIds: ["p\(index)a", "p\(index)b"], day: "d\(index)",
                                         start: Date(timeIntervalSince1970: Double(index) * 86_400),
                                         vector: [1, 0], labels: [], location: nil)
        }
        return result
    }

    private var pile: Pile {
        Pile(momentIds: (1...6).map { "m\($0)" }, days: 6, maxDayShare: 0.2, height: 0.3, center: [0.5, 0.5])
    }

    private func group(_ id: String, key: String, moments: [String], center: GeoPoint? = nil) -> SplitGroup {
        SplitGroup(id: id, key: key, momentIds: moments, days: moments.count, where: facts, placeCenter: center)
    }

    private var splitA: [SplitGroup] {
        [group("A1", key: "food", moments: ["m1", "m2", "m3"]), group("A2", key: "table", moments: ["m4", "m5"])]
    }

    private var splitB: [SplitGroup] {
        [group("B1", key: "0|evening|weekday", moments: ["m1", "m2", "m3"], center: place),
         group("B2", key: "1|morning|weekend", moments: ["m4", "m5", "m6"])]
    }

    private var sample: [SampledPhoto] {
        (1...6).map { SampledPhoto(momentId: "m\($0)", photoId: "p\($0)a", a: "A0", b: "B0") }
    }

    private func answer(_ json: String) -> RoundOneAnswer {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(RoundOneAnswer.self, from: Data(json.utf8))
    }

    private func answerA(names: [String] = ["Dinner", "Desk"], pile pileName: String = "Meals") -> RoundOneAnswer {
        answer("""
        {"sensitive":false,"pile_name":"\(pileName)","pile_noun":"meal","chosen":"A","groups":[
        {"from":["A1"],"name":"\(names[0])","noun":"dinner","same_part":"food","evidence":["food"]},
        {"from":["A2"],"name":"\(names[1])","noun":"desk","same_part":"table","evidence":[]}],
        "drop_groups":[],"not_in_pile":[],"two_kinds":false}
        """)
    }

    private func apply(_ answer: RoundOneAnswer, existing: [ThemeRow] = []) -> [ThemeRow] {
        let big = existing.first { $0.kind == .big }
        return ThemeLibrary.apply(answer, to: big, pile: pile, moments: moments, groups: (splitA, splitB),
                                  sample: sample, existing: existing)
    }

    private func smalls(_ rows: [ThemeRow]) -> [ThemeRow] { rows.filter { $0.kind == .small } }
    private func small(_ rows: [ThemeRow], _ name: String) -> ThemeRow? { smalls(rows).first { $0.name == name } }

    // MARK: - D4 / D5 / D7

    func testSensitiveAnswerMarksSensitiveNoSmallThemes() throws {
        let sensitive = answer("""
        {"sensitive":true,"pile_name":null,"chosen":"none","groups":[],"drop_groups":[],"not_in_pile":[]}
        """)
        let rows = apply(sensitive)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .big)
        XCTAssertEqual(rows[0].status, .sensitive)
        XCTAssertTrue(smalls(rows).isEmpty)
        // a theme that was fine before keeps its small rows, retired, same ids
        let earlier = apply(answerA())
        let later = apply(sensitive, existing: earlier)
        XCTAssertEqual(later.first { $0.kind == .big }?.status, .sensitive)
        XCTAssertEqual(Set(later.map(\.id)), Set(earlier.map(\.id)))
        XCTAssertEqual(smalls(later).map(\.status), [.retired, .retired])
    }

    /// A re-ask answered without `pile_noun` keeps the noun the theme had.
    func testReaskWithoutNounKeepsTheOldNoun() throws {
        let earlier = apply(answerA())
        XCTAssertEqual(earlier.first { $0.kind == .big }?.noun, "meal")
        let later = apply(answer(#"{"pile_name":"Meals","chosen":"none","groups":[]}"#), existing: earlier)
        XCTAssertEqual(later.first { $0.kind == .big }?.noun, "meal")
        let renamed = apply(answer(#"{"pile_name":"Meals","pile_noun":"food","chosen":"none"}"#), existing: later)
        XCTAssertEqual(renamed.first { $0.kind == .big }?.noun, "food")
    }

    func testFirstAnswerBuildsBigAndSmallRows() throws {
        let rows = apply(answerA())
        let big = try XCTUnwrap(rows.first { $0.kind == .big })
        XCTAssertEqual(big.name, "Meals")
        XCTAssertEqual(big.noun, "meal")
        XCTAssertEqual(big.samePart, "")
        XCTAssertEqual(big.split, "A")
        XCTAssertEqual(big.status, .active)
        XCTAssertEqual(big.center, [0.5, 0.5])
        XCTAssertEqual(big.members.count, 12)
        XCTAssertEqual(big.lastAskedCount, 12)
        let dinner = try XCTUnwrap(small(rows, "Dinner"))
        XCTAssertEqual(dinner.parentId, big.id)
        XCTAssertEqual(dinner.rule, .content(evidence: ["food"]))
        XCTAssertEqual(dinner.members, ["p1a", "p1b", "p2a", "p2b", "p3a", "p3b"])
        // empty evidence falls back to the source group's label key
        XCTAssertEqual(small(rows, "Desk")?.rule, .content(evidence: ["table"]))
    }

    /// Content rows get their groups' look, and keep only the evidence
    /// labels that are sharp in their groups (decision 2).
    func testFirstAnswerGivesContentRowsACenterAndSharpEvidence() throws {
        var labelled = moments
        let looks: [Int: [Float]] = [1: [1, 0], 2: [0.8, 0.6], 3: [1, 0], 4: [0, 1], 5: [0.6, 0.8], 6: [0, 1]]
        for index in 1...6 {
            // Nine generic labels that sort before `cat` must not crowd it out of the table.
            var labels = (0..<9).map { LabelScore(id: "a\($0)", confidence: 0.9) }
                + [LabelScore(id: "outdoor", confidence: 0.9)]
            if index <= 3 { labels.append(LabelScore(id: "cat", confidence: 0.9)) }
            if index == 4 || index == 5 { labels.append(LabelScore(id: "table", confidence: 0.9)) }
            let old = try XCTUnwrap(labelled["m\(index)"])
            labelled[old.id] = Moment(id: old.id, photoIds: old.photoIds, day: old.day, start: old.start,
                                      vector: looks[index]!, labels: labels, location: nil)
        }
        let catPile = answer("""
        {"sensitive":false,"pile_name":"Cats","chosen":"A","groups":[
        {"from":["A1"],"name":"Cat","evidence":["a0","outdoor","cat"]},
        {"from":["A2"],"name":"Table","evidence":["a0","outdoor"]}],"not_in_pile":[]}
        """)
        let rows = ThemeLibrary.apply(catPile, to: nil, pile: pile, moments: labelled, groups: (splitA, splitB),
                                      sample: sample, existing: [])
        let cat = try XCTUnwrap(small(rows, "Cat"))
        XCTAssertEqual(cat.rule, .content(evidence: ["cat"]), "generic labels are in every moment: not sharp")
        let center = try XCTUnwrap(cat.center)
        XCTAssertEqual(center, MomentBuilder.meanCenter([[1, 0], [0.8, 0.6], [1, 0]]))
        XCTAssertFalse(center.isEmpty)
        // No sharp evidence left: the source group's key, as before.
        let table = try XCTUnwrap(small(rows, "Table"))
        XCTAssertEqual(table.rule, .content(evidence: ["table"]))
        XCTAssertEqual(table.center, MomentBuilder.meanCenter([[0, 1], [0.6, 0.8]]))
        XCTAssertEqual(rows.first { $0.kind == .big }?.center, [0.5, 0.5], "the big row keeps the pile's look")
    }

    func testOccasionRuleParsesGroupKeys() throws {
        let byOccasion = answer("""
        {"sensitive":false,"pile_name":"Meals","chosen":"B","groups":[
        {"from":["B1"],"name":"Weekday dinner","evidence":[]},
        {"from":["B2"],"name":"Weekend breakfast","evidence":[]}],"not_in_pile":[]}
        """)
        let rows = apply(byOccasion)
        let dinner = try XCTUnwrap(small(rows, "Weekday dinner"))
        XCTAssertEqual(dinner.rule, .occasion(keys: [OccasionKey(place: place, daypart: "evening",
                                                                   weekpart: "weekday")]))
        XCTAssertEqual(dinner.where, facts)
        XCTAssertEqual(small(rows, "Weekend breakfast")?.rule,
                       .occasion(keys: [OccasionKey(place: nil, daypart: "morning", weekpart: "weekend")]))
        XCTAssertTrue(smalls(rows).allSatisfy { $0.center == nil }, "occasion rows have no look")
    }

    func testReaskKeepsIdsOfSameNames() throws {
        let first = apply(answerA())
        let second = apply(answerA(), existing: first)
        XCTAssertEqual(second.count, first.count)
        XCTAssertEqual(Set(second.map(\.id)), Set(first.map(\.id)))
        XCTAssertEqual(second.first { $0.kind == .big }?.id, first.first { $0.kind == .big }?.id)
    }

    func testReaskNewNameGetsNewIdMissingRetired() throws {
        let first = apply(answerA())
        let second = apply(answerA(names: ["Dinner", "Workspace"]), existing: first)
        XCTAssertEqual(small(second, "Dinner")?.id, small(first, "Dinner")?.id)
        let fresh = try XCTUnwrap(small(second, "Workspace"))
        XCTAssertFalse(first.map(\.id).contains(fresh.id))
        XCTAssertEqual(fresh.status, .active)
        let desk = try XCTUnwrap(small(second, "Desk"))
        XCTAssertEqual(desk.id, small(first, "Desk")?.id)
        XCTAssertEqual(desk.status, .retired)
    }

    func testRetiredNameComingBackGetsOldId() throws {
        let first = apply(answerA())
        let second = apply(answerA(names: ["Dinner", "Workspace"]), existing: first)
        let third = apply(answerA(), existing: second)
        let desk = try XCTUnwrap(small(third, "Desk"))
        XCTAssertEqual(desk.id, small(first, "Desk")?.id)
        XCTAssertEqual(desk.status, .active)
        XCTAssertEqual(small(third, "Workspace")?.status, .retired)
    }

    func testChangedSplitRetiresOldSmall() throws {
        let first = apply(answerA())
        let byOccasion = answer("""
        {"sensitive":false,"pile_name":"Meals","chosen":"B","groups":[
        {"from":["B1"],"name":"Weekday dinner","evidence":[]}],"not_in_pile":[]}
        """)
        let second = apply(byOccasion, existing: first)
        XCTAssertEqual(second.first { $0.kind == .big }?.split, "B")
        XCTAssertEqual(small(second, "Dinner")?.status, .retired)
        XCTAssertEqual(small(second, "Desk")?.status, .retired)
        let fresh = try XCTUnwrap(small(second, "Weekday dinner"))
        XCTAssertEqual(fresh.status, .active)
        XCTAssertFalse(first.map(\.id).contains(fresh.id))
        // going back to split A with the old names re-activates the old ids
        let third = apply(answerA(), existing: second)
        XCTAssertEqual(small(third, "Dinner")?.status, .active)
        XCTAssertEqual(small(third, "Dinner")?.id, small(first, "Dinner")?.id)
        XCTAssertEqual(small(third, "Weekday dinner")?.status, .retired)
    }

    func testRenameKeepsId() throws {
        let first = apply(answerA())
        let second = apply(answerA(pile: "Family meals"), existing: first)
        let before = try XCTUnwrap(first.first { $0.kind == .big })
        let after = try XCTUnwrap(second.first { $0.kind == .big })
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.name, "Family meals")
    }

    func testNotInPileImagesLeaveBigMembers() throws {
        let out = answer("""
        {"sensitive":false,"pile_name":"Meals","chosen":"A","groups":[
        {"from":["A1"],"name":"Dinner","evidence":["food"]}],"not_in_pile":[6, 2, 99]}
        """)
        let rows = apply(out)
        let big = try XCTUnwrap(rows.first { $0.kind == .big })
        XCTAssertEqual(big.members.count, 8)
        XCTAssertFalse(big.members.contains("p6a"))
        XCTAssertFalse(big.members.contains("p2b"))
        XCTAssertEqual(big.lastAskedCount, 8)
        XCTAssertEqual(small(rows, "Dinner")?.members, ["p1a", "p1b", "p3a", "p3b"])
    }

    // MARK: - D8

    func testDeletedPhotoLeavesStoreAndEveryThemeList() throws {
        let rows = apply(answerA())
        let result = ThemeLibrary.removing(["p1a", "p4b"], from: rows)
        XCTAssertEqual(result.count, rows.count)
        for row in result {
            XCTAssertFalse(row.members.contains("p1a"))
            XCTAssertFalse(row.members.contains("p4b"))
        }
        XCTAssertEqual(small(result, "Dinner")?.members.count, 5)
    }

    func testAllPhotosDeletedRemovesRow() throws {
        let rows = apply(answerA())
        let deleted: Set<String> = ["p4a", "p4b", "p5a", "p5b"]
        let result = ThemeLibrary.removing(deleted, from: rows)
        XCTAssertNil(small(result, "Desk"))
        XCTAssertNotNil(small(result, "Dinner"))
        XCTAssertNotNil(result.first { $0.kind == .big })
    }

    /// A sensitive or blocked row is the phone's memory of "never again":
    /// it is never removed, and keeps its photo ids, whatever the fetch.
    func testSensitiveAndBlockedRowsKeepTheirMembers() throws {
        var rows = apply(answerA())
        let big = try XCTUnwrap(rows.firstIndex { $0.kind == .big })
        rows[big].status = .sensitive
        let desk = try XCTUnwrap(rows.firstIndex { $0.name == "Desk" })
        rows[desk].status = .blocked
        let deleted = Set(rows[big].members)
        let result = ThemeLibrary.removing(deleted, from: rows)
        XCTAssertEqual(result.first { $0.kind == .big }?.members, rows[big].members)
        XCTAssertEqual(small(result, "Desk")?.members, rows[desk].members)
        XCTAssertNil(small(result, "Dinner"), "an active small row still goes with its photos")
    }

    func testEmptyRowNotRemovedWhenNothingWasDeletedFromIt() throws {
        var rows = apply(answerA())
        let index = try XCTUnwrap(rows.firstIndex { $0.name == "Desk" })
        rows[index].members = []
        let result = ThemeLibrary.removing(["p1a"], from: rows)
        XCTAssertNotNil(small(result, "Desk"))
    }

    // MARK: - Files

    func testLibraryRoundTripsAndLoadsEmptyFromGarbage() throws {
        let file = directory.appendingPathComponent("themes/library.json")
        let library = ThemeLibrary(file: file)
        XCTAssertEqual(library.load(), [])
        let rows = apply(answerA())
        try library.save(rows)
        XCTAssertEqual(library.load(), rows)
        try Data("not json {{".utf8).write(to: file)
        XCTAssertEqual(library.load(), [])
        let aside = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        XCTAssertTrue(aside.contains { $0.contains(".corrupt-") })
        try library.save(rows)
        XCTAssertEqual(library.load(), rows)
    }

    func testLibraryDropsUndecodableRowsOnly() throws {
        let file = directory.appendingPathComponent("library.json")
        let library = ThemeLibrary(file: file)
        try library.save(apply(answerA()))
        var text = try String(contentsOf: file, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"themes\":[", with: "\"themes\":[{\"id\":5},")
        try Data(text.utf8).write(to: file)
        XCTAssertEqual(library.load().count, 3)
    }

    // MARK: - Round log

    private func entry(_ key: String, reply: String, problem: RoundOneProblem? = nil,
                       at seconds: Double = 0) -> RoundLogEntry {
        RoundLogEntry(at: Date(timeIntervalSince1970: seconds), kind: "round1", themeId: "t", key: key,
                      reply: reply, usage: RoundUsage(promptTokens: 10, completionTokens: 5, costCny: 0.01,
                                                      model: "qwen"),
                      problem: problem, where: ["A1": "evening"])
    }

    func testRoundLogReusesAnswerForSameKey() throws {
        let log = RoundLog(file: directory.appendingPathComponent("themes/rounds.json"))
        XCTAssertNil(log.answer(for: "k"))
        try log.append(entry("k", reply: "first", at: 1))
        try log.append(entry("k", reply: "bad", problem: .notJSON, at: 2))
        try log.append(entry("k", reply: "", at: 3))
        try log.append(entry("other", reply: "x", at: 4))
        try log.append(entry("k", reply: "second", at: 5))
        XCTAssertEqual(log.answer(for: "k")?.reply, "second")
        XCTAssertEqual(RoundLog(file: directory.appendingPathComponent("themes/rounds.json"))
            .answer(for: "other")?.reply, "x")
        XCTAssertNil(log.answer(for: "none"))
    }

    func testRoundLogKeepsLastFiveHundred() throws {
        let log = RoundLog(file: directory.appendingPathComponent("rounds.json"))
        for index in 0..<503 { try log.append(entry("k\(index)", reply: "r\(index)", at: Double(index))) }
        let all = log.load()
        XCTAssertEqual(all.count, 500)
        XCTAssertEqual(all.first?.key, "k3")
        XCTAssertEqual(all.last?.key, "k502")
    }

    func testRoundUsageDecodesSnakeCase() throws {
        let json = #"{"prompt_tokens":120,"completion_tokens":30,"cost_cny":0.0042,"model":"qwen-vl"}"#
        let usage = try JSONDecoder().decode(RoundUsage.self, from: Data(json.utf8))
        XCTAssertEqual(usage, RoundUsage(promptTokens: 120, completionTokens: 30, costCny: 0.0042, model: "qwen-vl"))
    }

    func testRoundLogLoadsEmptyFromGarbage() throws {
        let file = directory.appendingPathComponent("rounds.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: file)
        XCTAssertEqual(RoundLog(file: file).load(), [])
    }

    func testRetiredCopyLosesItsCenter() throws {
        let first = apply(answerA())
        XCTAssertNotNil(small(first, "Desk")?.center)
        let second = apply(answerA(names: ["Dinner", "Workspace"]), existing: first)
        let desk = try XCTUnwrap(small(second, "Desk"))
        XCTAssertEqual(desk.status, .retired)
        XCTAssertNil(desk.center)
    }
}
