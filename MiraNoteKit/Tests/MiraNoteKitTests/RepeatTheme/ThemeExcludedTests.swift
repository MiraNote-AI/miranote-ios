import Foundation
import XCTest
@testable import MiraNoteKit

/// Photos round 1 said do not belong ("not_in_pile") stay out of the theme
/// and its small themes on every later run (decision 5b).
final class ThemeExcludedTests: XCTestCase {
    private var harness: ThemeHarness!

    override func setUp() {
        super.setUp()
        harness = ThemeHarness()
        harness.addTheme("x", base: 0, days: Array(1...6))
        harness.client.roundOneReply = { _, _ in
            #"{"sensitive": false, "pile_name": "Xs", "chosen": "none", "groups": [], "not_in_pile": [1]}"#
        }
    }

    override func tearDown() {
        harness = nil
        super.tearDown()
    }

    private func bigRow() throws -> ThemeRow {
        try XCTUnwrap(harness.themes.load().first { $0.kind == .big })
    }

    func testNotInPileImagesStayExcludedOnNextRun() async throws {
        let engine = harness.engine()
        _ = await engine.run(trigger: .foreground, deadline: nil)
        let first = try bigRow()
        let excluded = try XCTUnwrap(first.excluded)
        XCTAssertFalse(excluded.isEmpty)
        XCTAssertEqual(excluded, excluded.sorted())
        XCTAssertTrue(Set(first.members).isDisjoint(with: excluded))

        _ = await engine.run(trigger: .foreground, deadline: nil)
        let second = try bigRow()
        XCTAssertEqual(second.excluded, excluded)
        XCTAssertTrue(Set(second.members).isDisjoint(with: excluded), "back in members on the next run")
        XCTAssertEqual(second.members.count, first.members.count)
    }

    func testExcludedPhotosDoNotTriggerReask() async throws {
        // Half the pile is out: without the filter the list would reach 1.5x what was asked.
        harness.client.roundOneReply = { _, _ in
            #"{"sensitive": false, "pile_name": "Xs", "chosen": "none", "groups": [], "not_in_pile": [1, 2, 3]}"#
        }
        let engine = harness.engine()
        _ = await engine.run(trigger: .foreground, deadline: nil)
        let asked = harness.client.roundOneRequests.count
        let before = try bigRow().members.count
        // Same photos, every run: the excluded ones are in the pile each time.
        _ = await engine.run(trigger: .foreground, deadline: nil)
        _ = await engine.run(trigger: .foreground, deadline: nil)
        XCTAssertEqual(harness.client.roundOneRequests.count, asked, "not asked again")
        XCTAssertEqual(try bigRow().members.count, before)
    }

    func testExcludedPhotoStaysOutOfSmallLists() throws {
        let big = ThemeRow(id: "b", kind: .big, parentId: nil, name: "B", noun: "", samePart: "", split: "A",
                           status: .active, center: [0, 1], rule: nil, members: ["a", "b", "c"], lastAskedCount: 3,
                           flagged: false, followRatio: nil, where: nil, excluded: ["c"])
        let small = ThemeRow(id: "s", kind: .small, parentId: "b", name: "S", noun: "", samePart: "", split: "A",
                             status: .active, center: [1, 0], rule: .content(evidence: ["cat"]), members: [],
                             lastAskedCount: 0, flagged: false, followRatio: nil, where: nil)
        let moments = Dictionary(uniqueKeysWithValues: ["a", "b", "c"].enumerated().map { offset, id in
            (id, Moment(id: id, photoIds: [id], day: "d\(offset)",
                        start: Date(timeIntervalSince1970: Double(offset) * 86_400), vector: [1, 0],
                        labels: [LabelScore(id: "cat", confidence: 0.9)], location: nil))
        })
        let claim = ClaimResult(follows: ["b": 0], ratios: ["b": 1], flagged: [], frozen: [],
                                members: ["b": ["a", "b", "c"]], newPiles: [])
        let rows = ThemeEngine.writeBack(claim, to: [big, small], moments: moments, photos: [:],
                                         calendar: harness.calendar)
        XCTAssertEqual(rows.first { $0.id == "b" }?.members, ["a", "b"])
        XCTAssertEqual(rows.first { $0.id == "s" }?.members, ["a", "b"], "c is near and cat, yet excluded")
    }

    func testDeletedPhotoLeavesExcluded() throws {
        let big = ThemeRow(id: "b", kind: .big, parentId: nil, name: "B", noun: "", samePart: "", split: "none",
                           status: .active, center: nil, rule: nil, members: ["a", "b"], lastAskedCount: 2,
                           flagged: false, followRatio: nil, where: nil, excluded: ["c", "d"])
        let result = ThemeLibrary.removing(["c"], from: [big])
        XCTAssertEqual(result.first?.excluded, ["d"])
    }

    func testPruneDropsDeletedExcludedPhotos() async throws {
        let engine = harness.engine()
        _ = await engine.run(trigger: .foreground, deadline: nil)
        let excluded = try XCTUnwrap(bigRow().excluded)
        harness.library.assetsList.removeAll { excluded.contains($0.id) }
        _ = await engine.run(trigger: .foreground, deadline: nil)
        XCTAssertTrue(Set(try bigRow().excluded ?? []).isDisjoint(with: excluded))
    }

    func testRowWithoutExcludedDecodes() throws {
        let json = """
        {"id":"r","kind":"big","name":"N","noun":"","samePart":"","status":"active","members":["a"],
        "lastAskedCount":1,"flagged":false}
        """
        let row = try JSONDecoder().decode(ThemeRow.self, from: Data(json.utf8))
        XCTAssertNil(row.excluded)
        XCTAssertEqual(row.members, ["a"])
    }
}
