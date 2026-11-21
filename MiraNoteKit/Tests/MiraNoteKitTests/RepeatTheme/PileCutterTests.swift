import Foundation
import XCTest
@testable import MiraNoteKit

final class PileCutterTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let dimension = 128

    /// A unit vector at `distance` (cosine) from axis 0, tilted toward axis 1.
    private func groupBase(_ distance: Double) -> [Double] {
        var vector = [Double](repeating: 0, count: dimension)
        vector[0] = 1 - distance
        vector[1] = (1 - (1 - distance) * (1 - distance)).squareRoot()
        return vector
    }

    /// `days.count` near-identical moments around `center`: each one leans a
    /// little toward its own private axis, so they sit about 1e-4 apart.
    private func group(_ name: String, center: [Double], days: [Int], firstAxis: Int) -> [Moment] {
        days.enumerated().map { offset, day in
            var vector = center
            vector[firstAxis + offset] += 0.01
            return moment("\(name)\(offset)", day: day, vector: vector.map { Float($0) })
        }
    }

    private func moment(_ id: String, day: Int, vector: [Float]) -> Moment {
        Moment(id: id, photoIds: [id], day: String(format: "2026-%02d-%02d", 1 + day / 28, 1 + day % 28),
               start: base.addingTimeInterval(Double(day) * 86_400), vector: vector, labels: [], location: nil)
    }

    private func cut(_ moments: [Moment]) -> [Pile] {
        PileCutter.cut(moments, tree: ThemeTree.build(moments.map(\.vector)))
    }

    private func ids(_ piles: [Pile]) -> [[String]] {
        piles.map { $0.momentIds.sorted() }
    }

    // MARK: - B2: each cut rule

    func testFourDaysDoesNotQualifyFiveDoes() {
        let four = group("a", center: groupBase(0), days: [0, 1, 2, 3], firstAxis: 2)
        XCTAssertEqual(cut(four), [])

        let five = group("a", center: groupBase(0), days: [0, 1, 2, 3, 4], firstAxis: 2)
        let piles = cut(five)
        XCTAssertEqual(ids(piles), [["a0", "a1", "a2", "a3", "a4"]])
        XCTAssertEqual(piles.first?.days, 5)
        XCTAssertEqual(piles.first?.maxDayShare ?? 0, 0.2, accuracy: 1e-12)
    }

    func testThirtyOnePercentDayFailsThirtyPasses() {
        // 10 moments, 3 of them on one day: 30% passes.
        let ten = group("a", center: groupBase(0), days: [0, 0, 0, 1, 2, 3, 4, 5, 6, 7], firstAxis: 2)
        let piles = cut(ten)
        XCTAssertEqual(piles.count, 1)
        XCTAssertEqual(piles.first?.momentIds.count, 10)
        XCTAssertEqual(piles.first?.days, 8)
        XCTAssertEqual(piles.first?.maxDayShare, 0.3)

        // 100 moments, 31 of them on one day: 31% fails, even with 70 days.
        let days = [Int](repeating: 0, count: 31) + Array(1...69)
        XCTAssertEqual(cut(group("b", center: groupBase(0), days: days, firstAxis: 2)), [])
    }

    func testFailingNodeSplitsDownToFloor() {
        // A qualifies (5 days); B is one day's worth. Together they fail on share.
        let partA = group("a", center: groupBase(0), days: [0, 1, 2, 3, 4], firstAxis: 2)
        let farB = group("b", center: groupBase(0.3), days: [5, 5, 5, 5, 5], firstAxis: 10)
        // Root at ~0.3 (> floor) fails, so it splits and A is found.
        XCTAssertEqual(ids(cut(partA + farB)), [["a0", "a1", "a2", "a3", "a4"]])

        let nearB = group("b", center: groupBase(0.15), days: [5, 5, 5, 5, 5], firstAxis: 10)
        // Root at ~0.15 (<= floor) fails and stops there: nothing below is tried.
        XCTAssertEqual(cut(partA + nearB), [])
    }

    func testQualifyingNodeSplitsOnlyWhenBothChildrenQualify() {
        let partA = group("a", center: groupBase(0), days: [0, 1, 2, 3, 4], firstAxis: 2)
        let fiveDays = group("b", center: groupBase(0.3), days: [5, 6, 7, 8, 9], firstAxis: 10)
        // Both children qualify: two piles.
        XCTAssertEqual(Set(ids(cut(partA + fiveDays))),
                       [["a0", "a1", "a2", "a3", "a4"], ["b0", "b1", "b2", "b3", "b4"]])

        let fourDays = group("b", center: groupBase(0.3), days: [5, 6, 7, 8], firstAxis: 10)
        // One child fails: the qualifying parent is the pile.
        let piles = cut(partA + fourDays)
        XCTAssertEqual(ids(piles), [["a0", "a1", "a2", "a3", "a4", "b0", "b1", "b2", "b3"]])
        XCTAssertEqual(piles.first?.days, 9)
        XCTAssertEqual(Double(piles.first?.height ?? 0), 0.3, accuracy: 0.01)
    }

    func testQualifyingNodeWithALeafChildIsNotSplit() {
        // A 5-day group plus one far-off moment: the root's right child is a
        // leaf, so the root stays one pile even though the group qualifies.
        let partA = group("a", center: groupBase(0), days: [0, 1, 2, 3, 4, 5], firstAxis: 2)
        let lone = group("z", center: groupBase(0.3), days: [9], firstAxis: 20)
        XCTAssertEqual(ids(cut(partA + lone)), [["a0", "a1", "a2", "a3", "a4", "a5", "z0"]])
    }

    func testNodeAboveTopAlwaysSplits() {
        // The union qualifies (9 days) but sits at ~0.8 > top: it is split,
        // A is a pile and the 4-day B is not.
        let partA = group("a", center: groupBase(0), days: [0, 1, 2, 3, 4], firstAxis: 2)
        let partB = group("b", center: groupBase(0.8), days: [5, 6, 7, 8], firstAxis: 10)
        XCTAssertEqual(ids(cut(partA + partB)), [["a0", "a1", "a2", "a3", "a4"]])
    }

    func testPileCenterIsTheNormalizedMean() throws {
        let partA = group("a", center: groupBase(0), days: [0, 1, 2, 3, 4], firstAxis: 2)
        let pile = try XCTUnwrap(cut(partA).first)
        let length = pile.center.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        XCTAssertEqual(length, 1, accuracy: 1e-5)
        XCTAssertLessThan(MomentBuilder.cosineDistance(pile.center, partA[0].vector), 1e-3)
    }

    // MARK: - B3: same photos, same piles

    /// Eight themes of different sizes and spreads, plus scattered noise.
    private func mixedLibrary() -> [Moment] {
        var generator = SeededGenerator(seed: 42)
        var moments: [Moment] = []
        for theme in 0..<8 {
            let center = randomUnitVector(dimension: dimension, using: &generator)
            for index in 0..<(4 + theme * 2) {
                let noise = randomUnitVector(dimension: dimension, using: &generator)
                let vector = zip(center, noise).map { $0 + 0.35 * $1 }
                let day = Int.random(in: 0..<60, using: &generator)
                moments.append(moment("t\(theme)-\(index)", day: day, vector: vector))
            }
        }
        for index in 0..<30 {
            moments.append(moment("n\(index)", day: Int.random(in: 0..<60, using: &generator),
                                  vector: randomUnitVector(dimension: dimension, using: &generator)))
        }
        return moments
    }

    func testSameInputSamePilesTwice() {
        let moments = mixedLibrary()
        let first = cut(moments)
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, cut(moments))
    }

    func testShuffledInputSamePiles() {
        let moments = mixedLibrary()
        let expected = cut(moments)
        var generator = SeededGenerator(seed: 9)
        for _ in 0..<3 {
            let shuffled = cut(moments.shuffled(using: &generator))
            XCTAssertEqual(shuffled.map(\.momentIds), expected.map(\.momentIds))
            XCTAssertEqual(shuffled.map(\.days), expected.map(\.days))
            XCTAssertEqual(shuffled.map(\.maxDayShare), expected.map(\.maxDayShare))
            for (got, want) in zip(shuffled, expected) {
                XCTAssertEqual(got.height, want.height, accuracy: 1e-5)
                XCTAssertLessThan(MomentBuilder.cosineDistance(got.center, want.center), 1e-5)
            }
        }
    }

    // MARK: - Size

    func testFiveThousandMomentsPerformance() {
        var generator = SeededGenerator(seed: 5000)
        let moments = (0..<5000).map { index in
            moment("m\(index)", day: index % 300, vector: randomUnitVector(dimension: 768, using: &generator))
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(options: options) {
            let start = Date()
            let piles = cut(moments)
            let seconds = Date().timeIntervalSince(start)
            print("PileCutterTests: 5000 moments x 768-d, tree + cut in \(String(format: "%.2f", seconds)) s, "
                  + "\(piles.count) piles")
        }
    }
}
