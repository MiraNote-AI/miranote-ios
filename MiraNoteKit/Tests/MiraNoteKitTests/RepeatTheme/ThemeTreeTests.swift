import Foundation
import XCTest
@testable import MiraNoteKit

final class ThemeTreeTests: XCTestCase {
    func testTreeMatchesNaiveUPGMAOnSmallInput() {
        var generator = SeededGenerator(seed: 7)
        let vectors = (0..<40).map { _ in randomUnitVector(dimension: 8, using: &generator) }
        let tree = ThemeTree.build(vectors)

        let expected = naiveUPGMA(vectors)
        var actual: [Merge] = []
        for index in vectors.count..<(2 * vectors.count - 1) {
            let node = tree.node(index)
            actual.append(Merge(leaves: node.leaves.sorted(), height: Double(node.height)))
        }
        XCTAssertEqual(tree.root, 2 * vectors.count - 2)
        XCTAssertEqual(tree.node(tree.root).leaves.sorted(), Array(0..<40))
        XCTAssertEqual(actual.count, expected.count)
        let sortedActual = actual.sorted { $0.leaves.lexicographicallyPrecedes($1.leaves) }
        let sortedExpected = expected.sorted { $0.leaves.lexicographicallyPrecedes($1.leaves) }
        for (got, want) in zip(sortedActual, sortedExpected) {
            XCTAssertEqual(got.leaves, want.leaves)
            XCTAssertEqual(got.height, want.height, accuracy: 1e-5)
        }
        // Internal nodes come in merge order: heights never go down.
        let heights = (vectors.count..<(2 * vectors.count - 1)).map { tree.node($0).height }
        XCTAssertEqual(heights, heights.sorted())
    }

    func testLeafNodesHaveNoChildren() {
        let tree = ThemeTree.build([[1, 0], [0, 1], [1, 0.1]])
        for index in 0..<3 {
            let node = tree.node(index)
            XCTAssertNil(node.left)
            XCTAssertNil(node.right)
            XCTAssertEqual(node.leaves, [index])
            XCTAssertEqual(node.height, 0)
        }
        let root = tree.node(tree.root)
        XCTAssertEqual(root.leaves.sorted(), [0, 1, 2])
        // The two near-identical vectors merge first.
        XCTAssertEqual(tree.node(3).leaves.sorted(), [0, 2])
    }

    func testZeroAndMixedLengthVectorsAreAtDistanceOne() {
        // Same lengths, one zero vector.
        let zero = ThemeTree.build([[1, 0], [0, 0], [1, 0.01]])
        XCTAssertEqual(zero.node(3).leaves.sorted(), [0, 2])
        XCTAssertEqual(zero.height(zero.root), 1, accuracy: 1e-6)
        // A vector of another print revision.
        let mixed = ThemeTree.build([[1, 0], [1, 0, 0], [1, 0.01]])
        XCTAssertEqual(mixed.node(3).leaves.sorted(), [0, 2])
        XCTAssertEqual(mixed.height(mixed.root), 1, accuracy: 1e-6)
    }

    func testSingleVectorIsALeafRoot() {
        let tree = ThemeTree.build([[1, 0]])
        XCTAssertEqual(tree.root, 0)
        XCTAssertEqual(tree.node(0).leaves, [0])
    }

    // MARK: - Reference

    private struct Merge {
        let leaves: [Int]
        let height: Double
    }

    /// Textbook UPGMA, O(n^3): repeatedly merge the two clusters with the
    /// smallest mean pairwise distance between their original members.
    private func naiveUPGMA(_ vectors: [[Float]]) -> [Merge] {
        let count = vectors.count
        var distance = [[Double]](repeating: [Double](repeating: 0, count: count), count: count)
        for left in 0..<count {
            for right in 0..<count where left != right {
                distance[left][right] = Double(MomentBuilder.cosineDistance(vectors[left], vectors[right]))
            }
        }
        var clusters = (0..<count).map { [$0] }
        var merges: [Merge] = []
        while clusters.count > 1 {
            var best = (Double.infinity, 0, 0)
            for left in 0..<clusters.count {
                for right in (left + 1)..<clusters.count {
                    var sum = 0.0
                    for member in clusters[left] {
                        for other in clusters[right] { sum += distance[member][other] }
                    }
                    let mean = sum / Double(clusters[left].count * clusters[right].count)
                    if mean < best.0 { best = (mean, left, right) }
                }
            }
            let merged = (clusters[best.1] + clusters[best.2]).sorted()
            merges.append(Merge(leaves: merged, height: best.0))
            clusters.remove(at: best.2)
            clusters[best.1] = merged
        }
        return merges
    }
}

/// A small deterministic random source (SplitMix64) so tests repeat exactly.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// A random direction in `dimension` dimensions, unit length.
func randomUnitVector(dimension: Int, using generator: inout SeededGenerator) -> [Float] {
    let raw = (0..<dimension).map { _ in Float.random(in: -1...1, using: &generator) }
    let length = raw.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
    return raw.map { $0 / length }
}
