import XCTest
@testable import MiraNoteKit

/// Round 2 before a push (spec 6.13): Qwen's per-photo answer, what is
/// left of the candidates, and the two names lists it compares with.
final class RoundTwoTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_795_262_400)  // 2026-11-21 12:00 UTC

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testParsesTheAnswerShape() throws {
        let text = """
        Sure: {"photos": [{"id": 1, "belongs": true, "dup_of": null, "poor": false, "sensitive": false},
        {"id": 3, "belongs": true, "dup_of": 1, "poor": true, "sensitive": true}, {"belongs": true}],
        "similar_to": [{"name": "Sunset", "level": "\u{5F88}\u{50CF}"}, {"name": " ", "level": "x"}]}
        """
        let answer = try XCTUnwrap(RoundTwoAnswer.parse(text))
        XCTAssertEqual(answer.photos, [
            RoundTwoAnswer.Photo(id: 1, belongs: true, dupOf: nil, poor: false, sensitive: false),
            RoundTwoAnswer.Photo(id: 3, belongs: true, dupOf: 1, poor: true, sensitive: true)
        ], "an entry without an id is left out")
        XCTAssertEqual(answer.similarTo, [RoundTwoAnswer.Similar(name: "Sunset", level: "\u{5F88}\u{50CF}")],
                       "a blank name is no name")
        XCTAssertEqual(RoundTwoAnswer.parse(#"{"photos": [], "similar_to": []}"#)?.similarTo, [])
        XCTAssertEqual(RoundTwoAnswer.parse(#"{"photos": [{"id": 2}]}"#)?.photos,
                       [RoundTwoAnswer.Photo(id: 2, belongs: false, dupOf: nil, poor: false, sensitive: false)],
                       "unsaid belongs is not belonging")
        XCTAssertNil(RoundTwoAnswer.parse("no json"))
        XCTAssertNil(RoundTwoAnswer.parse(#"{"similar_to": []}"#), "no photos list: not an answer")
    }

    func testRoundTwoDropsWrongDuplicatePoorSensitiveThenCountsDays() throws {
        let candidates = Dictionary(uniqueKeysWithValues: (1...9).map { ($0, "p\($0)") })
        var days: [String: String] = [:]
        for number in 1...9 { days["p\(number)"] = "2026-10-0\(number)" }
        days["p9"] = days["p1"]  // the same day as p1
        let aesthetics = ["p3": 0.9, "p4": 0.4, "p7": 0.2, "p8": 0.8]
        let answer = try XCTUnwrap(RoundTwoAnswer.parse("""
        {"photos": [
          {"id": 1, "belongs": true, "dup_of": null, "poor": false, "sensitive": false},
          {"id": 2, "belongs": false, "dup_of": null, "poor": false, "sensitive": false},
          {"id": 3, "belongs": true, "dup_of": 4, "poor": false, "sensitive": false},
          {"id": 4, "belongs": true, "dup_of": null, "poor": false, "sensitive": false},
          {"id": 5, "belongs": true, "dup_of": null, "poor": true, "sensitive": false},
          {"id": 6, "belongs": true, "dup_of": null, "poor": false, "sensitive": true},
          {"id": 7, "belongs": true, "dup_of": 8, "poor": false, "sensitive": false},
          {"id": 8, "belongs": true, "dup_of": null, "poor": false, "sensitive": false},
          {"id": 9, "belongs": true, "dup_of": null, "poor": false, "sensitive": false},
          {"id": 12, "belongs": true, "dup_of": null, "poor": false, "sensitive": false}
        ], "similar_to": []}
        """))
        let left = RoundTwo.survivors(answer, candidates: candidates, aesthetics: aesthetics, days: days)
        // 2 does not belong, 4 is 3's duplicate with less aesthetics, 5 poor,
        // 6 sensitive, 7 is 8's duplicate with less; 12 was never sent.
        XCTAssertEqual(left.photos, ["p1", "p3", "p8", "p9"])
        XCTAssertEqual(left.days, 3, "p9 is on p1's day")

        let unanswered = try XCTUnwrap(RoundTwoAnswer.parse(#"{"photos": [{"id": 1, "belongs": true}]}"#))
        XCTAssertEqual(RoundTwo.survivors(unanswered, candidates: candidates, aesthetics: [:], days: days).photos,
                       ["p1"], "a candidate the answer skips is not kept")
    }

    func testBlockedNamesAlwaysInComparisonList() {
        func entry(_ name: String?, daysAgo: Double, mode: String = "repeat", debug: Bool = false,
                   themeId: String = "other") -> LedgerEntry {
            var entry = LedgerEntry(pushId: UUID().uuidString, isDebug: debug, belongsTo: "2026-10-01", groupKey: "k",
                                    photoIds: [], bucket: .other, place: nil,
                                    score: FragmentScore(r: 0, s: 0, p: 0, n: 0, u: 0, a: 0, base: 0, multiplier: 1,
                                                         bucket: .other, total: 0, days: 0, pushable: true),
                                    body: "", question: "", questionType: "",
                                    scheduledFor: now.addingTimeInterval(-daysAgo * 86_400))
            entry.mode = mode
            entry.themeId = themeId
            entry.themeName = name
            return entry
        }
        var removed = entry("Taken back", daysAgo: 3)
        removed.removedReason = .replan
        removed.removedAt = now
        let ledger = [
            entry("Sky", daysAgo: 10), entry("Sky", daysAgo: 20), entry("Old", daysAgo: 70),
            entry("Debug", daysAgo: 1, debug: true), entry("Fragment", daysAgo: 1, mode: "life_fragment"),
            entry("  ", daysAgo: 2), entry(nil, daysAgo: 2), entry("Self", daysAgo: 5, themeId: "t1"), removed,
            entry("Coffee", daysAgo: 59)
        ]
        let rows = [
            ThemeHarness.row("b1", name: "Scale", members: [], lastAsked: 0, center: [], status: .blocked),
            ThemeHarness.row("b2", name: "Old", members: [], lastAsked: 0, center: [], status: .blocked),
            ThemeHarness.row("b3", name: "Scale", members: [], lastAsked: 0, center: [], status: .blocked),
            ThemeHarness.row("b4", name: "", members: [], lastAsked: 0, center: [], status: .blocked),
            ThemeHarness.row("t1", name: "Self", members: [], lastAsked: 0, center: []),
            ThemeHarness.row("s1", name: "Pills", members: [], lastAsked: 0, center: [], status: .sensitive)
        ]
        let lists = RoundTwo.comparisonLists(ledger: ledger, rows: rows, themeId: "t1", now: now, calendar: calendar)
        XCTAssertEqual(lists.pushed, ["Sky", "Coffee"],
                       "repeat pushes of other themes within 60 days, once each; no debug, no blank, none taken back")
        XCTAssertEqual(lists.blocked, ["Scale", "Old"], "every blocked name, however old, once each")

        let many = (0..<30).map { entry("Theme \($0)", daysAgo: 1) }
        let blocked = (0..<60).map {
            ThemeHarness.row("x\($0)", name: "Blocked \($0)", members: [], lastAsked: 0, center: [], status: .blocked)
        }
        let capped = RoundTwo.comparisonLists(ledger: many, rows: blocked, themeId: "t1", now: now, calendar: calendar)
        XCTAssertEqual(capped.pushed.count, 20)
        XCTAssertEqual(capped.blocked.count, 50)
    }
}
