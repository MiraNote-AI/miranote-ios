import Foundation
import XCTest
@testable import MiraNoteKit

/// What the debug page "Themes" reads off the snapshot (spec 6.10, F1):
/// each theme's days, its judge calls and a small theme's "where" lines.
final class ThemeSnapshotTests: XCTestCase {
    private static let usage = RoundUsage(promptTokens: 1, completionTokens: 1, costCny: 0, model: "qwen-test")

    private static func entry(_ key: String, kind: String = "round1", themeId: String?, reply: String = "{}",
                              where lines: [String: String] = [:], minute: Int) -> RoundLogEntry {
        RoundLogEntry(at: ThemeHarness.start.addingTimeInterval(Double(minute) * 60), kind: kind, themeId: themeId,
                      key: key, reply: reply, usage: usage, problem: nil, where: lines)
    }

    private static func small(_ id: String, parent: String, name: String) -> ThemeRow {
        ThemeRow(id: id, kind: .small, parentId: parent, name: name, noun: "", samePart: "", split: "B",
                 status: .active, center: nil, rule: nil, members: [], lastAskedCount: 0, flagged: false,
                 followRatio: nil, where: nil)
    }

    private let dinner = ThemeHarness.row("b", name: "Dinner", members: [], lastAsked: 8, center: [])
    private let sky = ThemeHarness.row("o", name: "Sky", members: [], lastAsked: 6, center: [])
    private let weekday = ThemeSnapshotTests.small("s", parent: "b", name: "Weekday dinner")

    /// A new pile's answer (no theme id yet) and its shorten call, another
    /// pile's answer, a re-ask of Dinner, then two round-2 calls.
    private var snapshot: ThemeSnapshot {
        let first = #"{"pile_name": "Dinner", "chosen": "B", "groups": [{"from": ["B1"], "name": "Weekday dinner"}]}"#
        let reask = #"{"pile_name": "Dinner", "chosen": "B","#
            + #" "groups": [{"from": ["B2", "B3"], "name": "Weekday dinner"}]}"#
        let rounds = [
            Self.entry("k1", themeId: nil, reply: first, where: ["B1": "line 1", "B2": "line 2"], minute: 1),
            Self.entry("k1-shorten", kind: "shorten", themeId: nil, minute: 2),
            Self.entry("k2", themeId: nil, reply: #"{"pile_name": "Sky", "chosen": "none"}"#, minute: 3),
            Self.entry("k3", themeId: "b", reply: reask, where: ["B2": "line 2b", "B3": "line 3"], minute: 4),
            Self.entry("r2-s", kind: "round2", themeId: "s", minute: 5),
            Self.entry("r2-o", kind: "round2", themeId: "o", minute: 6)
        ]
        return ThemeSnapshot(runs: [], piles: [], follows: [:], themes: [dinner, weekday, sky], rounds: rounds)
    }

    func testRoundsOfABigThemeHoldTheAnswerThatNamedIt() {
        XCTAssertEqual(snapshot.entries(of: dinner).map(\.key), ["k3", "k1-shorten", "k1"], "newest first")
        XCTAssertEqual(snapshot.entries(of: sky).map(\.key), ["r2-o", "k2"])
    }

    func testRoundsOfASmallThemeHoldItsBigThemesAnswersThatNamedIt() {
        XCTAssertEqual(snapshot.entries(of: weekday).map(\.key), ["r2-s", "k3", "k1-shorten", "k1"])
        let other = Self.small("t", parent: "b", name: "Weekend dinner")
        XCTAssertEqual(snapshot.entries(of: other).map(\.key), [], "no answer named it")
    }

    func testWhereLinesOfTheNewestAnswerThatNamedTheGroup() {
        XCTAssertEqual(snapshot.whereLines(of: weekday), ["line 2b", "line 3"])
        XCTAssertEqual(snapshot.whereLines(of: dinner), [], "a big theme has no group")
        XCTAssertEqual(snapshot.whereLines(of: Self.small("t", parent: "b", name: "Weekend dinner")), [])
    }

    func testAnAnswerThatIsNotJSONNamesNothing() {
        var broken = snapshot
        broken.rounds = [Self.entry("k9", themeId: nil, reply: "no json", where: ["B1": "line"], minute: 1)]
        XCTAssertEqual(broken.entries(of: dinner).map(\.key), [])
        XCTAssertEqual(broken.whereLines(of: weekday), [])
    }

    /// Two big themes named alike: an answer with no theme id goes to
    /// neither; one with an id goes to its own theme only.
    func testSameNamedBigThemesShareNoAnswerByName() {
        let twin = ThemeHarness.row("b2", name: "Dinner", members: [], lastAsked: 5, center: [])
        let reply = #"{"pile_name": "Dinner", "chosen": "none"}"#
        let rounds = [Self.entry("old", themeId: nil, reply: reply, minute: 1),
                      Self.entry("own", themeId: "b2", reply: reply, minute: 2)]
        let snapshot = ThemeSnapshot(runs: [], piles: [], follows: [:], themes: [dinner, twin], rounds: rounds)
        XCTAssertEqual(snapshot.entries(of: dinner).map(\.key), [])
        XCTAssertEqual(snapshot.entries(of: twin).map(\.key), ["own"])
    }

    /// Two small themes of one big theme named alike: no answer and no
    /// "where" line is given to either by name.
    func testSameNamedSmallThemesShowNoWhereLine() {
        let twin = Self.small("s2", parent: "b", name: "Weekday dinner")
        var shared = snapshot
        shared.themes.append(twin)
        XCTAssertEqual(shared.whereLines(of: weekday), [])
        XCTAssertEqual(shared.whereLines(of: twin), [])
        XCTAssertEqual(shared.entries(of: weekday).map(\.key), ["r2-s"], "only its own calls")
        XCTAssertEqual(shared.entries(of: twin).map(\.key), [])
    }

    /// A new pile's answer carries the theme it made; when the library is
    /// lost and the stored answer is used again, the theme gets that id back.
    func testNewPileAnswerCarriesTheNewThemesId() async throws {
        let harness = ThemeHarness()
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        _ = await engine.run(trigger: .foreground, deadline: nil)
        let big = try XCTUnwrap(harness.bigRow(with: "x-1"))
        XCTAssertEqual(harness.rounds.load().map(\.themeId), [big.id])
        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.entries(of: big).count, 1)

        try FileManager.default.removeItem(at: harness.directory.appendingPathComponent("library.json"))
        _ = await engine.run(trigger: .foreground, deadline: nil)
        XCTAssertEqual(harness.rounds.load().count, 1, "the stored answer is used")
        XCTAssertEqual(harness.bigRow(with: "x-1")?.id, big.id)
    }

    func testSnapshotCountsEachThemesDays() async throws {
        let harness = ThemeHarness()
        harness.addTheme("x", base: 0, days: Array(1...6))
        // Two more photos on days already counted.
        harness.addBurst("x", days: [1, 2], extra: 1)
        let engine = harness.engine()
        _ = await engine.run(trigger: .foreground, deadline: nil)
        let big = try XCTUnwrap(harness.bigRow(with: "x-1"))
        XCTAssertEqual(big.members.count, 8)
        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.days[big.id], 6)
    }
}
