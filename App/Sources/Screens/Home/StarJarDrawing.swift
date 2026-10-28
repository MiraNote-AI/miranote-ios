import SwiftUI

// MARK: - Jar drawing

/// Where the jar's parts sit in its frame: a lid, a short neck, rounded
/// shoulders and a body with soft bottom corners.
struct JarGeometry {
    /// Width over height of the whole jar, lid included.
    static let aspect: CGFloat = 0.8

    let size: CGSize

    var lid: CGRect {
        let width = size.width * 0.5
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height * 0.06)
    }

    var mouthWidth: CGFloat { size.width * 0.44 }
    /// The bottom of the neck: where dropping stars come in.
    var mouthY: CGFloat { lid.maxY + size.height * 0.035 }
    var shoulderY: CGFloat { mouthY + size.height * 0.12 }
    var corner: CGFloat { size.width * 0.16 }
    static let stroke: CGFloat = 1.5

    /// The inside of the body, where stars may lie.
    var interior: JarInterior {
        let inset = Self.stroke + 2
        return JarInterior(
            rect: CGRect(
                x: inset, y: shoulderY, width: size.width - 2 * inset, height: size.height - shoulderY - inset
            ),
            corner: corner - inset
        )
    }

    func body(closed: Bool) -> Path {
        let left = (size.width - mouthWidth) / 2
        let right = left + mouthWidth
        let bottom = size.height - Self.stroke / 2
        let side = Self.stroke / 2
        let far = size.width - side
        var path = Path()
        path.move(to: CGPoint(x: left, y: lid.maxY))
        path.addLine(to: CGPoint(x: left, y: mouthY))
        path.addQuadCurve(to: CGPoint(x: side, y: shoulderY), control: CGPoint(x: side, y: mouthY))
        path.addLine(to: CGPoint(x: side, y: bottom - corner))
        path.addQuadCurve(to: CGPoint(x: side + corner, y: bottom), control: CGPoint(x: side, y: bottom))
        path.addLine(to: CGPoint(x: far - corner, y: bottom))
        path.addQuadCurve(to: CGPoint(x: far, y: bottom - corner), control: CGPoint(x: far, y: bottom))
        path.addLine(to: CGPoint(x: far, y: shoulderY))
        path.addQuadCurve(to: CGPoint(x: right, y: mouthY), control: CGPoint(x: far, y: mouthY))
        path.addLine(to: CGPoint(x: right, y: lid.maxY))
        if closed { path.closeSubpath() }
        return path
    }
}

/// Clear glass: a faint white body behind the stars, an ink hairline.
struct JarGlass: View {
    let geometry: JarGeometry

    var body: some View {
        ZStack(alignment: .topLeading) {
            geometry.body(closed: true)
                .fill(Color.white.opacity(0.3))
            geometry.body(closed: false)
                .stroke(Palette.ink.opacity(0.18), style: StrokeStyle(lineWidth: JarGeometry.stroke, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Two strokes of light down the front glass's left side, over the stars.
struct JarShine: View {
    let geometry: JarGeometry

    var body: some View {
        let size = geometry.size
        Path { path in
            let left = size.width * 0.085
            path.move(to: CGPoint(x: left, y: geometry.shoulderY + size.height * 0.06))
            path.addLine(to: CGPoint(x: left, y: size.height * 0.62))
            path.move(to: CGPoint(x: left, y: size.height * 0.67))
            path.addLine(to: CGPoint(x: left, y: size.height * 0.71))
        }
        .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct JarLid: View {
    let geometry: JarGeometry

    var body: some View {
        let lid = geometry.lid
        RoundedRectangle(cornerRadius: lid.height * 0.35)
            .fill(Color(hex: 0xC6B298))
            .overlay(
                RoundedRectangle(cornerRadius: lid.height * 0.35)
                    .strokeBorder(Palette.ink.opacity(0.14), lineWidth: 1)
            )
            .frame(width: lid.width, height: lid.height)
            .offset(x: lid.minX, y: lid.minY)
            .accessibilityHidden(true)
    }
}

// MARK: - Pile

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
