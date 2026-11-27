import Foundation
import XCTest
@testable import MiraNoteKit

// swiftlint:disable type_body_length
/// Which piles and themes the engine asks Qwen about, and what it keeps
/// (D1, D4, D5, C5, spec 6.5-6.7).
final class ThemeEngineTests: XCTestCase {
    private var harness: ThemeHarness!

    override func setUp() {
        super.setUp()
        harness = ThemeHarness()
    }

    override func tearDown() {
        harness = nil
        super.tearDown()
    }

    private func run(_ engine: ThemeEngine, deadline: Date? = nil) async -> ThemeRunReport {
        await engine.run(trigger: .foreground, deadline: deadline)
    }

    func testOnlyNewPilesAndGrownThemesAreAsked() async {
        harness.addTheme("x", base: 0, days: Array(1...6))
        harness.addTheme("y", base: 1, days: Array(1...6))
        let engine = harness.engine()

        var report = await run(engine)
        XCTAssertEqual(report.piles.count, 2)
        XCTAssertEqual(report.asked, 2, "two new piles, each asked once")
        XCTAssertEqual(harness.themes.load().filter { $0.kind == .big }.count, 2)

        report = await run(engine)
        XCTAssertEqual(report.asked, 0, "followed piles that did not grow are not asked")
        XCTAssertEqual(harness.client.roundOneRequests.count, 2)

        // A new pile z, and x grows from 6 to 9 photos (9 / 6 = 1.5).
        let xName = harness.bigRow(with: "x-1")?.name
        harness.addTheme("z", base: 2, days: Array(1...6))
        harness.addBurst("x", days: [1, 2, 3], extra: 1)
        report = await run(engine)
        XCTAssertEqual(report.asked, 2)
        let requests = harness.client.roundOneRequests
        XCTAssertEqual(requests.count, 4)
        let reask = requests.dropFirst(2).filter { $0.old != nil }
        XCTAssertEqual(reask.map { $0.old?.pileName }, [xName], "only x is re-asked, with its old name")
        XCTAssertEqual(requests.dropFirst(2).filter { $0.old == nil }.count, 1, "z is asked as a new pile")
        XCTAssertEqual(harness.themes.load().filter { $0.kind == .big }.count, 3)
        XCTAssertEqual(harness.bigRow(with: "x-1")?.lastAskedCount, 9)
    }

    func testSameSituationNotAskedTwice() async throws {
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        _ = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 1)
        let name = harness.bigRow(with: "x-1")?.name

        // The library is lost: x is a new pile again, with the same sample.
        try FileManager.default.removeItem(at: harness.directory.appendingPathComponent("library.json"))
        let report = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 1, "the stored answer is used")
        XCTAssertEqual(report.asked, 0)
        XCTAssertEqual(harness.bigRow(with: "x-1")?.name, name)
    }

    func testChangedGroupsAreAskedAgain() async throws {
        harness.addTheme("x", base: 0, days: [1, 2, 3, 4], labels: [LabelScore(id: "soup", confidence: 0.9)])
        harness.addTheme("x", base: 0, days: [5, 6, 7, 8], labels: [LabelScore(id: "noodle", confidence: 0.9)])
        harness.client.roundOneReply = { request, _ in
            request.splitA.count == 2
                ? #"{"pile_name": "Meals", "chosen": "A", "groups": [{"from": ["A1"], "name": "Noodles"},"#
                    + #" {"from": ["A2"], "name": "Soup"}]}"#
                : #"{"pile_name": "Soup days", "chosen": "none"}"#
        }
        let engine = harness.engine()
        let library = harness.directory.appendingPathComponent("library.json")
        _ = await run(engine)
        XCTAssertEqual(harness.themes.load().filter { $0.kind == .small }.count, 2)

        // Same groups: the stored answer is used (D4).
        try FileManager.default.removeItem(at: library)
        _ = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 1)
        XCTAssertEqual(harness.themes.load().filter { $0.kind == .small }.count, 2)

        // The noodle label is gone: split A is one group now, a new question.
        try FileManager.default.removeItem(at: library)
        let changed = harness.photos.loadAll().values.filter { ["x-5", "x-6", "x-7", "x-8"].contains($0.id) }.map {
            ThemePhoto(id: $0.id, takenAt: $0.takenAt, location: $0.location, labels: [], aesthetics: $0.aesthetics,
                       faces: $0.faces, isTheme: $0.isTheme, print: $0.print, printRevision: $0.printRevision)
        }
        try harness.photos.upsert(changed, calendar: harness.calendar)
        _ = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 2, "exactly one new call")
        XCTAssertEqual(harness.client.roundOneRequests.last?.splitA.count, 1)
        XCTAssertEqual(harness.bigRow(with: "x-1")?.name, "Soup days")
    }

    func testGrowthAtOnePointFiveReasks() async {
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        _ = await run(engine)
        let before = harness.bigRow(with: "x-1")
        XCTAssertEqual(before?.lastAskedCount, 6)

        harness.addBurst("x", days: [1, 2, 3], extra: 1)
        _ = await run(engine)
        let requests = harness.client.roundOneRequests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.old?.pileName, "Theme1")
        XCTAssertEqual(requests.last?.old?.groups, [])
        let after = harness.bigRow(with: "x-1")
        XCTAssertEqual(after?.id, before?.id, "a re-ask keeps the theme's id")
        XCTAssertEqual(after?.name, "Theme2")
        XCTAssertEqual(after?.lastAskedCount, 9)
    }

    func testOnePointFourDoesNot() async {
        harness.addTheme("x", base: 0, days: Array(1...5))
        let engine = harness.engine()
        _ = await run(engine)
        harness.addBurst("x", days: [1, 2], extra: 1)  // 7 / 5 = 1.4
        _ = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 1)
        let row = harness.bigRow(with: "x-1")
        XCTAssertEqual(row?.members.count, 7, "tonight's list grows without asking")
        XCTAssertEqual(row?.lastAskedCount, 5)
    }

    func testMergedPileReasksOnlyTheThemeOverTheLine() async throws {
        harness.addTheme("x", base: 0, days: Array(1...8))
        // Two old themes now share pile x. Alpha keeps its 4 old photos
        // (4 / 4); Beta keeps its 2 and takes x-7, x-8, the photos nearer its
        // center (4 / 2 = 2).
        let alpha = ThemeHarness.row("alpha", name: "Alpha", members: (1...4).map { "x-\($0)" }, lastAsked: 4,
                                     center: ThemeHarness.vector(base: 3, noise: 0))
        let beta = ThemeHarness.row("beta", name: "Beta", members: ["x-5", "x-6"], lastAsked: 2,
                                    center: ThemeHarness.vector(base: 0, noise: 0))
        try harness.themes.save([alpha, beta])

        let report = await run(harness.engine())
        XCTAssertEqual(report.asked, 1)
        let request = try XCTUnwrap(harness.client.roundOneRequests.first)
        XCTAssertEqual(request.old?.pileName, "Beta")
        XCTAssertEqual(request.dayCount, 4, "only Beta's part of the pile is sampled")
        XCTAssertTrue(Set(request.photoIds.values).isSubset(of: ["x-5", "x-6", "x-7", "x-8"]))
        let rows = harness.themes.load()
        XCTAssertEqual(Set(rows.first { $0.id == "alpha" }?.members ?? []), Set((1...4).map { "x-\($0)" }))
        XCTAssertEqual(Set(rows.first { $0.id == "beta" }?.members ?? []), ["x-5", "x-6", "x-7", "x-8"])
        XCTAssertEqual(rows.first { $0.id == "beta" }?.lastAskedCount, 4)
    }

    func testSensitiveThemeNeverSentAgain() async {
        harness.client.roundOneReply = { _, _ in #"{"sensitive": true, "chosen": "none", "groups": []}"# }
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        _ = await run(engine)
        XCTAssertEqual(harness.bigRow(with: "x-1")?.status, .sensitive)

        harness.addBurst("x", days: Array(1...6), extra: 1)  // 12 / 6 = 2
        let report = await run(engine)
        XCTAssertEqual(report.asked, 0)
        XCTAssertEqual(harness.client.roundOneRequests.count, 1)
        let rows = harness.themes.load()
        XCTAssertEqual(rows.count, 1, "the sensitive theme still holds its pile: no new theme")
        XCTAssertEqual(rows.first?.status, .sensitive)
    }

    func testBlockedThemeIsNotReaskedAndCanBeCleared() async throws {
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        _ = await run(engine)
        let id = try XCTUnwrap(harness.bigRow(with: "x-1")?.id)

        await engine.block(id)
        XCTAssertEqual(harness.bigRow(with: "x-1")?.status, .blocked)
        harness.addBurst("x", days: Array(1...6), extra: 1)
        _ = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 1, "a blocked theme is never sent")
        XCTAssertEqual(harness.bigRow(with: "x-1")?.status, .blocked)

        await engine.unblock(id)
        XCTAssertEqual(harness.bigRow(with: "x-1")?.status, .active)
    }

    func testClaimIsWrittenBackToTheRows() async throws {
        harness.addTheme("x", base: 0, days: Array(1...6))
        harness.addTheme("y", base: 1, days: [1, 2, 3])  // theme photos, too few days for a pile
        let flagged = ThemeHarness.row("flagged", name: "Half", members: ["x-1", "x-2", "y-1", "y-2", "y-3"],
                                       lastAsked: 5, center: ThemeHarness.vector(base: 0, noise: 0))
        let lost = ThemeHarness.row("lost", name: "Lost", members: ["y-1", "y-2"], lastAsked: 2,
                                    center: ThemeHarness.vector(base: 1, noise: 0))
        let blocked = ThemeHarness.row("blocked", name: "Off", members: ["y-3"], lastAsked: 1,
                                       center: ThemeHarness.vector(base: 1, noise: 0), status: .blocked)
        try harness.themes.save([flagged, lost, blocked])

        let engine = harness.engine()
        let report = await run(engine)
        XCTAssertEqual(report.asked, 0, "x is followed and 6 / 5 is under 1.5")
        let rows = Dictionary(uniqueKeysWithValues: harness.themes.load().map { ($0.id, $0) })
        XCTAssertEqual(rows["flagged"]?.followRatio ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertEqual(rows["flagged"]?.flagged, true)
        XCTAssertEqual(rows["flagged"]?.status, .active)
        XCTAssertEqual(Set(rows["flagged"]?.members ?? []), Set((1...6).map { "x-\($0)" }))
        XCTAssertEqual(rows["lost"]?.status, .frozen)
        XCTAssertEqual(rows["lost"]?.followRatio, 0)
        XCTAssertEqual(rows["lost"]?.members, ["y-1", "y-2"], "a frozen theme keeps its list")
        XCTAssertEqual(rows["blocked"]?.status, .blocked, "a blocked theme is never set frozen")
        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.follows["flagged"], 0)
        XCTAssertNil(snapshot.follows["lost"])
        XCTAssertEqual(snapshot.piles.count, 1)
    }

    func testRoundFailureIsRetriedNextRunAndNotCached() async {
        harness.client.roundOneErrors = [ThemeRoundError.unreachable]
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        let failed = await run(engine)
        XCTAssertFalse(failed.failures.isEmpty)
        XCTAssertTrue(harness.themes.load().isEmpty, "the pile stays unnamed")
        XCTAssertTrue(harness.rounds.load().allSatisfy { $0.problem != nil || $0.reply.isEmpty })

        _ = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 2, "asked again on the next run")
        XCTAssertEqual(harness.bigRow(with: "x-1")?.name, "Theme2")
    }

    /// A 502 the model was paid for: its usage goes in the round log (the
    /// cost report counts every round), and it is asked again next run.
    func testModelFailureLogsItsUsage() async {
        let spent = RoundUsage(promptTokens: 1978, completionTokens: 0, costCny: 0.0004, model: "qwen-test")
        harness.client.roundOneErrors = [ThemeRoundError.model(reason: "timeout", usage: spent)]
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        _ = await run(engine)
        let logged = harness.rounds.load()
        XCTAssertEqual(logged.map(\.kind), ["round1"])
        XCTAssertEqual(logged.first?.usage, spent)
        XCTAssertEqual(logged.first?.reply, "", "no answer to reuse")

        _ = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 2, "asked again on the next run")
        XCTAssertEqual(harness.bigRow(with: "x-1")?.name, "Theme2")
    }

    func testBadAnswerCoolsTheAskForSevenDays() async {
        harness.client.roundOneReply = { _, number in
            number == 1 ? "no json here" : #"{"pile_name": "Fine", "chosen": "none"}"#
        }
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        _ = await run(engine)
        XCTAssertEqual(harness.rounds.load().map(\.problem), [.notJSON])
        XCTAssertTrue(harness.themes.load().isEmpty)
        let report = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 1, "cooling: no new round-1 call")
        XCTAssertEqual(report.asked, 0)
        XCTAssertTrue(report.failures.contains { $0.hasSuffix("waiting after an unusable answer") })
        harness.clock.advance(8 * 86_400)
        _ = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 2)
        XCTAssertEqual(harness.bigRow(with: "x-1")?.name, "Fine")
    }

    func testShortenRoundOnceThenGroupDropped() async {
        let soup = [LabelScore(id: "soup", confidence: 0.9)]
        let noodle = [LabelScore(id: "noodle", confidence: 0.9)]
        harness.addTheme("x", base: 0, days: [1, 2, 3, 4], labels: soup)
        harness.addTheme("x", base: 0, days: [5, 6, 7, 8], labels: noodle)
        // A1 = noodle, A2 = soup (4 days each, then by key).
        harness.client.roundOneReply = { _, _ in
            #"""
            {"sensitive": false, "pile_name": "Meals", "pile_noun": "meal", "chosen": "A",
             "groups": [{"from": ["A1"], "name": "Abcdefghijk", "noun": "noodle", "same_part": "bowl",
                         "evidence": ["noodle"]},
                        {"from": ["A2"], "name": "Soup", "noun": "soup", "same_part": "bowl", "evidence": ["soup"]}]}
            """#
        }
        harness.client.shortenReply = { _ in #"{"items": [{"key": "A1", "name": "Abcdefghijkl", "same_part": "b"}]}"# }
        let engine = harness.engine()
        _ = await run(engine)

        XCTAssertEqual(harness.client.shortenItems.map { $0.map(\.key) }, [["A1"]])
        let rows = harness.themes.load()
        XCTAssertEqual(rows.first { $0.kind == .big }?.name, "Meals")
        XCTAssertEqual(rows.filter { $0.kind == .small }.map(\.name), ["Soup"], "still too long: dropped")
        let small = rows.first { $0.kind == .small }
        XCTAssertEqual(Set(small?.members ?? []), ["x-1", "x-2", "x-3", "x-4"])

        _ = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 1)
        XCTAssertEqual(harness.client.shortenItems.count, 1)
    }

    /// The small lists the ask sets are the ones every later run makes:
    /// content children split the big list by look, a photo in one at most.
    func testSmallListsAfterAskMatchNextRun() async throws {
        let soup = LabelScore(id: "soup", confidence: 0.9)
        harness.addTheme("x", base: 0, days: [1, 2, 3, 4], labels: [soup])
        harness.addTheme("x", base: 0, days: [5, 6, 7, 8], labels: [LabelScore(id: "noodle", confidence: 0.9)])
        // A soup-looking day that also shows some noodles: soup only, by look.
        harness.addTheme("x", base: 0, days: [9], labels: [soup, LabelScore(id: "noodle", confidence: 0.5)])
        for day in 1...9 {
            var look = ThemeHarness.vector(base: 0, noise: day)
            look[(5...8).contains(day) ? 2 : 1] = 0.3
            harness.analyzer.vectors["x-\(day)"] = look
        }
        harness.client.roundOneReply = { request, _ in
            let groups = request.splitA.compactMap { group -> String? in
                guard let label = group.tags?.first?.label else { return nil }
                return #"{"from": ["\#(group.id)"], "name": "\#(label)", "evidence": ["\#(label)"]}"#
            }
            return #"{"pile_name": "Meals", "chosen": "A", "groups": [\#(groups.joined(separator: ", "))]}"#
        }
        func smallLists() -> [String: [String]] {
            Dictionary(uniqueKeysWithValues: harness.themes.load().filter { $0.kind == .small }
                .map { ($0.name, $0.members) })
        }
        let engine = harness.engine()
        _ = await run(engine)
        let afterAsk = smallLists()
        XCTAssertEqual(Set(afterAsk["soup"] ?? []), ["x-1", "x-2", "x-3", "x-4", "x-9"])
        XCTAssertEqual(Set(afterAsk["noodle"] ?? []), ["x-5", "x-6", "x-7", "x-8"])
        XCTAssertTrue(Set(afterAsk["soup"] ?? []).isDisjoint(with: afterAsk["noodle"] ?? []))

        _ = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 1, "not asked again")
        XCTAssertEqual(smallLists(), afterAsk)
    }

    func testShortenedNamesAreUsed() async {
        harness.addTheme("x", base: 0, days: Array(1...6))
        harness.client.roundOneReply = { _, _ in #"{"pile_name": "Abcdefghijk", "chosen": "none"}"# }
        harness.client.shortenReply = { _ in #"{"items": [{"key": "pile", "name": "Short", "same_part": ""}]}"# }
        _ = await run(harness.engine())
        XCTAssertEqual(harness.bigRow(with: "x-1")?.name, "Short")
    }

    func testUnusableShortenReplyPutsThePileOnCooldown() async throws {
        harness.addTheme("x", base: 0, days: Array(1...6))
        harness.client.roundOneReply = { _, _ in #"{"pile_name": "Abcdefghijk", "chosen": "none"}"# }
        harness.client.shortenReply = { _ in "not json" }
        let engine = harness.engine()
        _ = await run(engine)
        let failed = try XCTUnwrap(harness.cooldown.load().first)
        XCTAssertEqual(Set(failed.photoIds), Set((1...6).map { "x-\($0)" }))
        XCTAssertNil(harness.bigRow(with: "x-1"))
        _ = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 1, "not asked again")
        XCTAssertEqual(harness.client.shortenItems.count, 1)
        XCTAssertEqual(harness.cooldown.load().count, 1)
    }

    func testReaskSendsAtMostTwelveOldGroupNames() async throws {
        harness.addTheme("x", base: 0, days: Array(1...6))
        let big = ThemeHarness.row("big", name: "Meals", members: (1...4).map { "x-\($0)" }, lastAsked: 4,
                                   center: ThemeHarness.vector(base: 0, noise: 0))
        let smalls = (1...15).map { index in
            ThemeRow(id: "small-\(index)", kind: .small, parentId: "big", name: "Group\(index)", noun: "",
                     samePart: "", split: "A", status: .active, center: nil, rule: nil, members: ["x-1"],
                     lastAskedCount: 1, flagged: false, followRatio: nil, where: nil)
        }
        try harness.themes.save([big] + smalls)
        _ = await run(harness.engine())  // 6 / 4 = 1.5
        let request = try XCTUnwrap(harness.client.roundOneRequests.first)
        XCTAssertEqual(request.old?.groups, (1...12).map { "Group\($0)" }, "the backend takes 12")
        XCTAssertLessThanOrEqual(request.photos.count, 20)
        XCTAssertEqual(request.photos.map(\.n), Array(1...request.photos.count))
        XCTAssertEqual(harness.client.roundOneImages.first?.map(\.n), request.photos.map(\.n))
    }
}
// swiftlint:enable type_body_length
