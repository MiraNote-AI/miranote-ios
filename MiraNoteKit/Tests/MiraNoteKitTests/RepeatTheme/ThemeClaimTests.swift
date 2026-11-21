import Foundation
import XCTest
@testable import MiraNoteKit

final class ThemeClaimTests: XCTestCase {
    /// One-photo moments: the moment id is the photo id. `day` numbers the day.
    private func moment(_ id: String, day: Int, vector: [Float] = [1, 0]) -> Moment {
        Moment(id: id, photoIds: [id], day: String(format: "2027-01-%02d", day),
               start: Date(timeIntervalSince1970: 1_799_020_800 + Double(day) * 86_400),
               vector: vector, labels: [], location: nil)
    }

    /// `count` moments named `prefix0`..., each on its own day from `firstDay`.
    private func moments(_ prefix: String, _ count: Int, firstDay: Int = 1,
                         vector: [Float] = [1, 0]) -> [Moment] {
        (0..<count).map { moment("\(prefix)\($0)", day: firstDay + $0 % 28, vector: vector) }
    }

    private func pile(_ members: [Moment], center: [Float] = [1, 0]) -> Pile {
        Pile(momentIds: members.map(\.id), days: Set(members.map(\.day)).count, maxDayShare: 0.1,
             height: 0.3, center: center)
    }

    private func big(_ id: String, members: [String], center: [Float]? = [1, 0],
                     status: ThemeStatus = .active) -> ThemeRow {
        ThemeRow(id: id, kind: .big, parentId: nil, name: id, noun: id, samePart: "", split: "A",
                 status: status, center: center, rule: nil, members: members,
                 lastAskedCount: members.count, flagged: false, followRatio: nil, where: nil)
    }

    private func claim(_ themes: [ThemeRow], _ piles: [Pile], _ all: [Moment],
                       window: Set<String>? = nil) -> ClaimResult {
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let everything = Set(all.map(\.id)).union(themes.flatMap(\.members))
        return ThemeClaim.claim(themes, piles: piles, moments: byId, window: window ?? everything)
    }

    // MARK: - Ratio and tiers (C1, C2)

    func testRatioUsesWindowOnlyDenominator() {
        // Ten old photos, four have left the window: 3 of the 6 left is 50%,
        // not 3 of 10 (30%, flagged).
        let old = moments("o", 10)
        let new = moments("n", 4, firstDay: 20)
        let tonight = Array(old.prefix(3)) + new
        let theme = big("rice", members: old.map(\.id))
        let window = Set(old.prefix(6).map(\.id) + new.map(\.id))
        let result = claim([theme], [pile(tonight)], tonight, window: window)
        XCTAssertEqual(result.ratios["rice"], 0.5)
        XCTAssertEqual(result.follows["rice"], 0)
        XCTAssertTrue(result.flagged.isEmpty)
    }

    func testNoOldMembersInWindowFreezes() {
        let old = moments("o", 5)
        let tonight = moments("n", 6, firstDay: 20)
        let theme = big("rice", members: old.map(\.id))
        let result = claim([theme], [pile(tonight)], tonight, window: Set(tonight.map(\.id)))
        XCTAssertEqual(result.frozen, ["rice"])
        XCTAssertNil(result.follows["rice"])
        XCTAssertEqual(result.members["rice"], old.map(\.id))
        XCTAssertEqual(result.newPiles, [0])
    }

    func testTieFollowsMoreDays() {
        // Half the old photos in each pile: pile 0 holds them on one day,
        // pile 1 on two days, so pile 1 wins although it comes second.
        let sameDay = [moment("a0", day: 1), moment("a1", day: 1)]
        let twoDays = [moment("a2", day: 2), moment("a3", day: 3)]
        let others = moments("x", 5, firstDay: 10)
        let piles = [pile(sameDay + others), pile(twoDays)]
        let theme = big("sky", members: (sameDay + twoDays).map(\.id))
        let result = claim([theme], piles, sameDay + twoDays + others)
        XCTAssertEqual(result.ratios["sky"], 0.5)
        XCTAssertEqual(result.follows["sky"], 1)
        XCTAssertEqual(result.newPiles, [0])
    }

    func testFiftyPercentFollows() {
        let old = moments("o", 10)
        let tonight = Array(old.prefix(5)) + moments("n", 3, firstDay: 20)
        let result = claim([big("rice", members: old.map(\.id))], [pile(tonight)], old + tonight)
        XCTAssertEqual(result.follows["rice"], 0)
        XCTAssertTrue(result.flagged.isEmpty)
        XCTAssertTrue(result.frozen.isEmpty)
        XCTAssertEqual(result.newPiles, [])
    }

    func testThirtyPercentFollowsAndFlags() {
        let old = moments("o", 10)
        let tonight = Array(old.prefix(3)) + moments("n", 3, firstDay: 20)
        let result = claim([big("rice", members: old.map(\.id))], [pile(tonight)], old + tonight)
        XCTAssertEqual(result.follows["rice"], 0)
        XCTAssertEqual(result.ratios["rice"] ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(result.flagged, ["rice"])
        XCTAssertTrue(result.frozen.isEmpty)
        XCTAssertEqual(result.members["rice"], tonight.map(\.id))
    }

    func testNineteenPercentFreezesAndListUnchanged() {
        let old = moments("o", 100)
        let tonight = Array(old.prefix(19)) + moments("n", 3, firstDay: 20)
        let theme = big("rice", members: old.map(\.id))
        let result = claim([theme], [pile(tonight)], old + tonight)
        XCTAssertEqual(result.ratios["rice"] ?? 0, 0.19, accuracy: 1e-9)
        XCTAssertNil(result.follows["rice"])
        XCTAssertEqual(result.frozen, ["rice"])
        XCTAssertTrue(result.flagged.isEmpty)
        XCTAssertEqual(result.members["rice"], theme.members)
        XCTAssertEqual(result.newPiles, [0])
    }

    func testFrozenThemeRefollowsAtTwentyPercent() {
        let old = moments("o", 10)
        let tonight = Array(old.prefix(2)) + moments("n", 4, firstDay: 20)
        let theme = big("rice", members: old.map(\.id), status: .frozen)
        let result = claim([theme], [pile(tonight)], old + tonight)
        XCTAssertEqual(result.follows["rice"], 0)
        XCTAssertEqual(result.flagged, ["rice"])
        XCTAssertTrue(result.frozen.isEmpty)
        XCTAssertEqual(result.members["rice"], tonight.map(\.id))
    }

    func testSensitiveThemeStillClaimsItsPile() {
        // Its pile must not come back as a new pile and be sent to Qwen again.
        let old = moments("o", 6)
        let result = claim([big("private", members: old.map(\.id), status: .sensitive)], [pile(old)], old)
        XCTAssertEqual(result.follows["private"], 0)
        XCTAssertEqual(result.newPiles, [])
    }

    // MARK: - The five cases (C3)

    func testGrowing() {
        // "Rice": 51 old, tonight's pile of 56 holds 50 of them (98%).
        let old = moments("o", 51)
        let new = moments("n", 6, firstDay: 1)
        let tonight = Array(old.prefix(50)) + new
        let result = claim([big("rice", members: old.map(\.id))], [pile(tonight)], old + new)
        XCTAssertEqual(result.ratios["rice"] ?? 0, 50.0 / 51.0, accuracy: 1e-9)
        XCTAssertEqual(result.follows["rice"], 0)
        XCTAssertTrue(result.flagged.isEmpty)
        XCTAssertEqual(result.members["rice"], tonight.map(\.id))
        XCTAssertEqual(result.members["rice"]?.count, 56)
        XCTAssertEqual(result.newPiles, [])
    }

    func testSlightlyChanged() {
        let old = moments("o", 10)
        let tonight = Array(old.prefix(4)) + moments("n", 3, firstDay: 20)
        let result = claim([big("rice", members: old.map(\.id))], [pile(tonight)], old + tonight)
        XCTAssertEqual(result.follows["rice"], 0)
        XCTAssertEqual(result.flagged, ["rice"])
        XCTAssertEqual(result.members["rice"], tonight.map(\.id))
    }

    func testSplitOtherHalfBecomesNewPile() {
        // "Sky": 40 old; tonight the blue sky (12 old) left the sunsets (28 old).
        let old = moments("o", 40)
        let sunsets = Array(old.prefix(28)) + moments("s", 4, firstDay: 1)
        let blue = Array(old.suffix(12)) + moments("b", 5, firstDay: 1)
        let result = claim([big("sky", members: old.map(\.id))], [pile(blue), pile(sunsets)],
                           old + sunsets + blue)
        XCTAssertEqual(result.ratios["sky"] ?? 0, 0.7, accuracy: 1e-9)
        XCTAssertEqual(result.follows["sky"], 1)
        XCTAssertEqual(result.members["sky"], sunsets.map(\.id))
        XCTAssertEqual(result.newPiles, [0])
    }

    func testMergedKeepsBothThemesAndOwnPhotos() {
        // "Coffee" 12 old and "milk tea" 10 old run together into one drinks pile.
        let coffee = moments("c", 12)
        let tea = moments("t", 10, vector: [0, 1])
        let new = moments("n", 6, firstDay: 1, vector: [0.6, 0.8])
        let drinks = Array(coffee.prefix(11)) + Array(tea.prefix(9)) + new
        let result = claim([big("coffee", members: coffee.map(\.id), center: [1, 0]),
                            big("tea", members: tea.map(\.id), center: [0, 1])],
                           [pile(drinks)], coffee + tea + new)
        XCTAssertEqual(result.follows["coffee"], 0)
        XCTAssertEqual(result.follows["tea"], 0)
        XCTAssertEqual(result.newPiles, [])
        let coffeeTonight = Set(result.members["coffee"] ?? [])
        let teaTonight = Set(result.members["tea"] ?? [])
        XCTAssertTrue(coffeeTonight.isSuperset(of: coffee.prefix(11).map(\.id)))
        XCTAssertTrue(teaTonight.isSuperset(of: tea.prefix(9).map(\.id)))
        XCTAssertTrue(coffeeTonight.isDisjoint(with: teaTonight))
        XCTAssertEqual(coffeeTonight.union(teaTonight), Set(drinks.map(\.id)))
    }

    func testMismatchFreezes() {
        // "Flowers": 15 old scattered over three piles, 2 each (13%).
        let old = moments("f", 15)
        let piles = (0..<3).map { index in
            pile(Array(old[(2 * index)..<(2 * index + 2)]) + moments("p\(index)-", 5, firstDay: 1))
        }
        let all = old + (0..<3).flatMap { moments("p\($0)-", 5, firstDay: 1) }
        let theme = big("flowers", members: old.map(\.id))
        let result = claim([theme], piles, all)
        XCTAssertEqual(result.frozen, ["flowers"])
        XCTAssertNil(result.follows["flowers"])
        XCTAssertEqual(result.members["flowers"], theme.members)
        XCTAssertEqual(result.newPiles, [0, 1, 2])
    }

    // MARK: - Merged piles by look (C4)

    func testMergedOthersGoToNearestCenter() {
        // c1 looks like tea but stays coffee's: old photos stay with their theme.
        let c0 = moment("c0", day: 1, vector: [1, 0])
        let c1 = moment("c1", day: 2, vector: [0, 1])
        let t0 = moment("t0", day: 3, vector: [0, 1])
        let nearCoffee = moment("n0", day: 4, vector: [0.9, 0.1])
        let nearTea = moment("n1", day: 5, vector: [0.2, 0.8])
        let all = [c0, c1, t0, nearCoffee, nearTea]
        let result = claim([big("coffee", members: ["c0", "c1"], center: [1, 0]),
                            big("tea", members: ["t0"], center: [0, 1])], [pile(all)], all)
        XCTAssertEqual(result.members["coffee"], ["c0", "c1", "n0"])
        XCTAssertEqual(result.members["tea"], ["t0", "n1"])
    }
}
