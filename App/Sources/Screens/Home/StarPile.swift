import CoreGraphics
import Foundation

// The star jar's pile: where its stars lie, the same jar the same way
// every time. Beside StarJarDrawing.swift, which draws the jar round it.

/// The body's inside: a rectangle with rounded bottom corners.
struct JarInterior {
    let rect: CGRect
    let corner: CGFloat

    var width: CGFloat { rect.width }
    var midX: CGFloat { rect.midX }
    var midY: CGFloat { rect.midY }
}

/// A settled pile: rows from the bottom up, every other row offset half a
/// star, each star nudged and turned by its page's id -- the same jar
/// looks the same every time. Stars are as large as fits with the pile
/// filling at most two thirds of the jar; a crowd shrinks them further
/// only as far as it must to fit at all.
enum StarPile {
    struct Spot {
        let center: CGPoint
        let rotation: Double
    }

    static let largest: CGFloat = 64
    /// The size a crowd shrinks from to fit the whole jar.
    static let crowdLargest: CGFloat = 26
    static let smallest: CGFloat = 10
    /// The share of the jar's height a pile may fill.
    static let fillShare: CGFloat = 2.0 / 3.0

    static func layout(_ ids: [UUID], in interior: JarInterior) -> (starSize: CGFloat, spots: [Spot]) {
        let size = starSize(ids.count, in: interior)
        let perRow = slots(size: size, width: interior.width)
        var spots: [Spot] = []
        var row = 0
        var placed = 0
        while placed < ids.count {
            let count = min(perRow - row % 2, ids.count - placed)
            let rowWidth = CGFloat(count) * size
            let startX = interior.midX - rowWidth / 2 + size / 2
            let rowY = interior.rect.maxY - size / 2 - CGFloat(row) * size * 0.84 - 1
            for slot in 0..<count {
                let id = ids[placed + slot]
                let jittered = CGPoint(
                    x: startX + CGFloat(slot) * size + CGFloat(unit(id, 0) - 0.5) * size * 0.3,
                    y: rowY + CGFloat(unit(id, 1) - 0.5) * size * 0.16
                )
                spots.append(Spot(
                    center: inside(jittered, radius: size / 2, interior: interior),
                    rotation: (unit(id, 2) - 0.5) * 44
                ))
            }
            placed += count
            row += 1
        }
        return (size, spots)
    }

    /// The largest size whose pile fills no more than `fillShare` of the
    /// jar, up to `largest`; never below what a crowd needs to fit at all.
    static func starSize(_ count: Int, in interior: JarInterior) -> CGFloat {
        var size = largest
        while size > smallest, pileHeight(count, size: size, width: interior.width)
                > interior.rect.height * fillShare {
            size -= 1
        }
        var crowd = crowdLargest
        while crowd > smallest, pileHeight(count, size: crowd, width: interior.width)
                > interior.rect.height * 0.9 {
            crowd -= 1
        }
        return max(size, crowd)
    }

    /// How tall the rows of `count` stars of `size` stand.
    static func pileHeight(_ count: Int, size: CGFloat, width: CGFloat) -> CGFloat {
        rowsNeeded(count, size: size, width: width) * size * 0.84
    }

    /// Stars in a full (even) row: the width less a margin, a star apiece.
    private static func slots(size: CGFloat, width: CGFloat) -> Int {
        max(2, Int((width - size * 0.4) / size))
    }

    private static func rowsNeeded(_ count: Int, size: CGFloat, width: CGFloat) -> CGFloat {
        let perPair = 2 * slots(size: size, width: width) - 1
        let pairs = count / perPair
        let rest = count % perPair
        return CGFloat(pairs * 2 + (rest == 0 ? 0 : (rest > slots(size: size, width: width) ? 2 : 1)))
    }

    /// Keeps a star of `radius` clear of the walls and the rounded bottom
    /// corners.
    private static func inside(_ point: CGPoint, radius: CGFloat, interior: JarInterior) -> CGPoint {
        let rect = interior.rect.insetBy(dx: radius, dy: radius)
        var point = CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
        let corner = interior.corner
        let reach = corner - radius
        guard reach > 0 else { return point }
        for centerX in [interior.rect.minX + corner, interior.rect.maxX - corner] {
            let cornerCenter = CGPoint(x: centerX, y: interior.rect.maxY - corner)
            let inCornerX = centerX < interior.midX ? point.x < cornerCenter.x : point.x > cornerCenter.x
            guard inCornerX, point.y > cornerCenter.y else { continue }
            let dx = point.x - cornerCenter.x, dy = point.y - cornerCenter.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance > reach {
                point = CGPoint(x: cornerCenter.x + dx / distance * reach, y: cornerCenter.y + dy / distance * reach)
            }
        }
        return point
    }

    /// A number in 0..<1 drawn from the id's bytes: stable across launches,
    /// unlike `hashValue`.
    static func unit(_ id: UUID, _ salt: Int) -> Double {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let high = Int(bytes[(salt * 2) % 16]), low = Int(bytes[(salt * 2 + 1) % 16])
        return Double(high << 8 | low) / 65536
    }
}
