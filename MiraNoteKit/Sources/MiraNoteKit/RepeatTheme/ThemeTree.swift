import Accelerate
import Foundation

/// The full average-linkage (UPGMA) tree over moment vectors, on cosine
/// distance: what the repeat-theme finder cuts into piles.
///
/// Built the way SciPy's `linkage(pdist(M, 'cosine'), 'average')` builds it,
/// so the desktop reference script and the phone agree: the
/// nearest-neighbour-chain algorithm with Lance-Williams updates
/// `d(k, i+j) = (n_i d(k, i) + n_j d(k, j)) / (n_i + n_j)`, merges sorted by
/// height (stable), then numbered like SciPy. Leaves are `0..<n`; merge `k`
/// (in height order) is node `n + k`, its left child the lower number. A
/// tie goes to the previous chain element, then to the lower cluster index,
/// so the same vectors always give the same tree.
///
/// The pairwise distances are kept as one condensed Float32 matrix (5,000
/// moments take 50 MB; Double would take 100 MB); every distance and every
/// update is computed in Double and only stored as Float32. While the
/// distances are made, the vectors are also held once in Double (5,000 x
/// 768 take 31 MB).
final class ThemeTree: Sendable {
    struct Node: Equatable, Sendable {
        /// The children, nil for a leaf.
        let left: Int?
        let right: Int?
        /// The cosine distance at which the children merged; 0 for a leaf.
        let height: Float
        /// The leaf indices under this node, left to right.
        let leaves: [Int]
    }

    /// The number of input vectors.
    let leafCount: Int
    /// Per merge, in node order (node `leafCount + k` is entry `k`).
    private let lefts: [Int]
    private let rights: [Int]
    private let heights: [Float]

    private init(leafCount: Int, lefts: [Int], rights: [Int], heights: [Float]) {
        self.leafCount = leafCount
        self.lefts = lefts
        self.rights = rights
        self.heights = heights
    }

    /// The top node: the last merge, or the only leaf. -1 for no vectors.
    var root: Int {
        leafCount == 0 ? -1 : 2 * leafCount - 2
    }

    func node(_ index: Int) -> Node {
        guard let (left, right) = children(index) else {
            return Node(left: nil, right: nil, height: 0, leaves: [index])
        }
        return Node(left: left, right: right, height: height(index), leaves: leaves(index))
    }

    /// The two children, nil for a leaf.
    func children(_ index: Int) -> (Int, Int)? {
        index < leafCount ? nil : (lefts[index - leafCount], rights[index - leafCount])
    }

    func height(_ index: Int) -> Float {
        index < leafCount ? 0 : heights[index - leafCount]
    }

    /// The leaf indices under `index`, left to right.
    func leaves(_ index: Int) -> [Int] {
        var result: [Int] = []
        var stack = [index]
        while let next = stack.popLast() {
            if let (left, right) = children(next) {
                stack.append(right)
                stack.append(left)
            } else {
                result.append(next)
            }
        }
        return result
    }

    static func build(_ vectors: [[Float]]) -> ThemeTree {
        let count = vectors.count
        guard count > 1 else { return ThemeTree(leafCount: count, lefts: [], rights: [], heights: []) }
        var distances = condensedDistances(vectors)
        let merges = nearestNeighbourChain(&distances, count: count)

        // SciPy: stable sort by height, then renumber with a union-find.
        let ordered = merges.enumerated()
            .sorted { ($0.element.height, $0.offset) < ($1.element.height, $1.offset) }
            .map(\.element)
        var parent = Array(0..<(2 * count - 1))
        func find(_ start: Int) -> Int {
            var root = start
            while parent[root] != root { root = parent[root] }
            var node = start
            while parent[node] != root {
                let next = parent[node]
                parent[node] = root
                node = next
            }
            return root
        }
        var lefts: [Int] = []
        var rights: [Int] = []
        lefts.reserveCapacity(count - 1)
        rights.reserveCapacity(count - 1)
        for (offset, merge) in ordered.enumerated() {
            let first = find(merge.first)
            let second = find(merge.second)
            lefts.append(min(first, second))
            rights.append(max(first, second))
            parent[first] = count + offset
            parent[second] = count + offset
        }
        return ThemeTree(leafCount: count, lefts: lefts, rights: rights, heights: ordered.map(\.height))
    }

    // MARK: - Building

    private struct Merge {
        let first: Int
        let second: Int
        let height: Float
    }

    /// `1 - cosine similarity` for every pair, in Double, as SciPy's
    /// `pdist(..., 'cosine')` up to rounding (the vectors are scaled to unit
    /// length first; similarity clamped to [-1, 1]). A zero vector, or
    /// vectors of different lengths, are at distance 1, as in
    /// `MomentBuilder.cosineDistance`.
    private static func condensedDistances(_ vectors: [[Float]]) -> [Float] {
        let count = vectors.count
        let length = vectors[0].count
        guard length > 0, vectors.allSatisfy({ $0.count == length }) else { return pairwiseDistances(vectors) }
        var distances = [Float](repeating: 1, count: count * (count - 1) / 2)

        // All vectors as unit columns in Double (length x count); a zero
        // vector stays zero (similarity 0, distance 1).
        var transposed = [Double](repeating: 0, count: length * count)
        for (column, vector) in vectors.enumerated() {
            let norm = vector.reduce(0.0) { $0 + Double($1) * Double($1) }.squareRoot()
            guard norm > 0 else { continue }
            for (row, value) in vector.enumerated() { transposed[row * count + column] = Double(value) / norm }
        }
        // Similarities a block of rows at a time: block (rows x length) times
        // `transposed`.
        let blockRows = 64
        var block = [Double](repeating: 0, count: blockRows * length)
        var products = [Double](repeating: 0, count: blockRows * count)
        var position = 0
        for blockStart in stride(from: 0, to: count, by: blockRows) {
            let rows = min(blockRows, count - blockStart)
            for row in 0..<rows {
                for column in 0..<length {
                    block[row * length + column] = transposed[column * count + blockStart + row]
                }
            }
            vDSP_mmulD(block, 1, transposed, 1, &products, 1,
                       vDSP_Length(rows), vDSP_Length(count), vDSP_Length(length))
            distances.withUnsafeMutableBufferPointer { outputBuffer in
                let output = outputBuffer.baseAddress!
                products.withUnsafeBufferPointer { similarities in
                    for row in 0..<rows {
                        let first = blockStart + row
                        let rowSimilarities = similarities.baseAddress! + row * count
                        var second = first + 1
                        while second < count {
                            output[position] = Float(1 - min(1, max(-1, rowSimilarities[second])))
                            position += 1
                            second += 1
                        }
                    }
                }
            }
        }
        return distances
    }

    /// Mixed print revisions: rare, so the plain pairwise loop.
    private static func pairwiseDistances(_ vectors: [[Float]]) -> [Float] {
        var distances: [Float] = []
        distances.reserveCapacity(vectors.count * (vectors.count - 1) / 2)
        for first in vectors.indices {
            for second in (first + 1)..<vectors.count {
                distances.append(max(0, MomentBuilder.cosineDistance(vectors[first], vectors[second])))
            }
        }
        return distances
    }

    /// The condensed matrix as raw pointers. The scans below are the whole
    /// cost of a big library and must stay fast in a Debug build too.
    private struct Matrix {
        let distances: UnsafeMutablePointer<Float>
        /// Live cluster sizes; 0 once merged away.
        let sizes: UnsafeMutablePointer<Int>
        /// The pair `i < j` sits at `rows[i] + j - i - 1` (SciPy's layout).
        let rows: UnsafePointer<Int>
        let count: Int

        @inline(__always)
        func index(_ one: Int, _ other: Int) -> Int {
            one < other ? rows[one] + other - one - 1 : rows[other] + one - other - 1
        }

        /// The live cluster nearest to `cluster`, starting from `candidate`
        /// (the previous chain element). Scans in index order with a strict
        /// `<`, so a tie keeps the candidate, then the lowest index.
        func nearest(to cluster: Int, candidate: Int?) -> (cluster: Int, distance: Double) {
            var best = candidate ?? 0
            var nearest = candidate.map { Double(distances[index(cluster, $0)]) } ?? .infinity
            var other = 0
            while other < cluster {
                if sizes[other] > 0 {
                    let distance = Double(distances[rows[other] + cluster - other - 1])
                    if distance < nearest {
                        nearest = distance
                        best = other
                    }
                }
                other += 1
            }
            let row = distances + rows[cluster] - cluster - 1
            other = cluster + 1
            while other < count {
                if sizes[other] > 0 {
                    let distance = Double(row[other])
                    if distance < nearest {
                        nearest = distance
                        best = other
                    }
                }
                other += 1
            }
            return (best, nearest)
        }

        /// Merges `first` into `second` (`first < second`): Lance-Williams
        /// for average linkage, in Double, stored as Float32.
        func merge(_ first: Int, into second: Int) {
            let firstSize = Double(sizes[first])
            let secondSize = Double(sizes[second])
            sizes[second] += sizes[first]
            sizes[first] = 0
            var other = 0
            while other < count {
                if sizes[other] > 0 && other != second {
                    let toSecond = index(other, second)
                    distances[toSecond] = Float((firstSize * Double(distances[index(other, first)])
                                                 + secondSize * Double(distances[toSecond]))
                                                / (firstSize + secondSize))
                }
                other += 1
            }
        }
    }

    /// SciPy's `nn_chain`: follow nearest neighbours until two clusters are
    /// each other's nearest, merge them, repeat. Merge `x < y` drops `x` and
    /// puts the union in `y`'s slot. Merges come out in merge order, not
    /// height order.
    private static func nearestNeighbourChain(_ distances: inout [Float], count: Int) -> [Merge] {
        var merges: [Merge] = []
        merges.reserveCapacity(count - 1)
        var sizes = [Int](repeating: 1, count: count)
        let rows = (0..<count).map { count * $0 - $0 * ($0 + 1) / 2 }
        var chain: [Int] = []
        chain.reserveCapacity(count)

        distances.withUnsafeMutableBufferPointer { distanceBuffer in
            sizes.withUnsafeMutableBufferPointer { sizeBuffer in
                rows.withUnsafeBufferPointer { rowBuffer in
                    let matrix = Matrix(distances: distanceBuffer.baseAddress!, sizes: sizeBuffer.baseAddress!,
                                        rows: rowBuffer.baseAddress!, count: count)
                    for _ in 0..<(count - 1) {
                        if chain.isEmpty { chain.append((0..<count).first { matrix.sizes[$0] > 0 }!) }
                        while true {
                            // Prefer the previous chain element, so the chain cannot cycle.
                            let previous = chain.count > 1 ? chain[chain.count - 2] : nil
                            let next = matrix.nearest(to: chain[chain.count - 1], candidate: previous)
                            if next.cluster == previous {
                                let pair = chain.suffix(2).sorted()
                                chain.removeLast(2)
                                merges.append(Merge(first: pair[0], second: pair[1], height: Float(next.distance)))
                                matrix.merge(pair[0], into: pair[1])
                                break
                            }
                            chain.append(next.cluster)
                        }
                    }
                }
            }
        }
        return merges
    }
}
