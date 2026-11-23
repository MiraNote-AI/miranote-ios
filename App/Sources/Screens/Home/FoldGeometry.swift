import SwiftUI

// A port of design X's fold maths (debug/star-anim/X/proto.html): t
// (ms), p/q (progress), a/b (ends), k, w and z (spring and scale terms)
// read as the formulas they are; longer names would hide them. The page,
// its easing, its camera and how it folds onto its band; FoldDrawing.swift
// draws the strip, the knot and the star.
// swiftlint:disable identifier_name

/// A page ready to fold into its star, or to unfold from it (#206, design
/// X). Lengths are page points: the page is 360 wide; its top 560 fold
/// (`height`), folded in half at 280 and the top half in four rows of 70,
/// one of which (`row`) is the band the rest folds up onto.
struct StarPaper {
    /// The page as reading mode shows it, `fullHeight` tall.
    let page: Image
    let fullHeight: CGFloat
    /// The band's row in the top half, 0...3.
    let row: Int
    /// The band, 360 x 70: the folded-up page seen face up.
    let strip: Image
    /// The band softened, for the knot's and the star's faces.
    let face: Image
    /// The star's dress in the jar.
    let paint: StarPaint
    /// The page's soft warm shadow: `shadowMargin` round a 360 x 560 page.
    let shadow: Image

    static let width: CGFloat = 360
    static let height: CGFloat = 560
    static let half: CGFloat = 280
    static let tile: CGFloat = 70
    static let corner: CGFloat = 22
    static let shadowMargin: CGFloat = 70

    /// The band's top on the page.
    var bandTop: CGFloat { CGFloat(row) * Self.tile }
    /// The band's middle, from the page's middle (world units).
    var bandY: CGFloat { bandTop + Self.tile / 2 - Self.height / 2 }
}

/// The prototype's easing curves.
enum Ease {
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    static func clamp(_ x: CGFloat, _ a: CGFloat = 0, _ b: CGFloat = 1) -> CGFloat { max(a, min(b, x)) }
    /// Where `t` stands between `a` and `b`, 0...1.
    static func seg(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { clamp((t - a) / (b - a)) }
    static func out3(_ p: CGFloat) -> CGFloat { 1 - pow(1 - p, 3) }
    static func in2(_ p: CGFloat) -> CGFloat { p * p }
    static func inOut3(_ p: CGFloat) -> CGFloat { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
    static func sine(_ p: CGFloat) -> CGFloat { 0.5 - 0.5 * cos(.pi * p) }
    static func smooth(_ p: CGFloat) -> CGFloat { p * p * (3 - 2 * p) }
    static func outBack(_ p: CGFloat, _ k: CGFloat) -> CGFloat {
        let q = p - 1
        return 1 + (k + 1) * q * q * q + k * q * q
    }

    /// A damped spring 0 to 1, about 10% over.
    static func spring(_ p: CGFloat, _ w: CGFloat) -> CGFloat {
        if p <= 0 { return 0 }
        if p >= 1 { return 1 }
        return 1 - exp(-6.5 * p) * cos(w * p)
    }

    /// An underdamped spring, damping ratio `z`, angular frequency `w`.
    static func springZ(_ p: CGFloat, _ z: CGFloat, _ w: CGFloat) -> CGFloat {
        if p <= 0 { return 0 }
        if p >= 1 { return 1 }
        let wd = w * (1 - z * z).squareRoot()
        return 1 - exp(-z * w * p) * (cos(wd * p) + z * w / wd * sin(wd * p))
    }

    static func bounceOut(_ p: CGFloat) -> CGFloat {
        let n: CGFloat = 7.5625, d: CGFloat = 2.75
        if p < 1 / d { return n * p * p }
        if p < 2 / d { let q = p - 1.5 / d; return n * q * q + 0.75 }
        if p < 2.5 / d { let q = p - 2.25 / d; return n * q * q + 0.9375 }
        let q = p - 2.625 / d
        return n * q * q + 0.984375
    }

    /// A paper fold: eases in from rest, lands with speed (the snap),
    /// then a tiny rebound. Radians, 0 to pi.
    static func foldIn(_ t: CGFloat, _ t0: CGFloat, _ tl: CGFloat, _ settle: CGFloat) -> CGFloat {
        if t <= t0 { return 0 }
        if t < tl {
            let p = (t - t0) / (tl - t0)
            return .pi * (0.45 * smooth(p) + 0.55 * p * p)
        }
        let q = seg(t, tl, tl + settle)
        return .pi - 0.11 * sin(.pi * q) * (1 - q)
    }

    static func bezier(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ u: CGFloat) -> CGPoint {
        let m = 1 - u
        return CGPoint(x: m * m * a.x + 2 * m * u * c.x + u * u * b.x, y: m * m * a.y + 2 * m * u * c.y + u * u * b.y)
    }
}

// MARK: - Camera

/// What the fold's camera sees: world points (page points from the
/// page's middle) at `zoom` design points apiece, `focus` at `anchor` on
/// screen. `scale` turns the prototype's 402 pt wide screen into this one.
struct FoldCamera {
    var zoom: CGFloat
    var focus: CGPoint
    var anchor: CGPoint
    var scale: CGFloat

    /// Screen points per world point.
    var z: CGFloat { zoom * scale }
    /// The perspective's focal length, in screen points.
    var focal: CGFloat { 950 * scale }

    func apply(to context: inout GraphicsContext) {
        context.translateBy(x: anchor.x, y: anchor.y)
        context.scaleBy(x: z, y: z)
        context.translateBy(x: -focus.x, y: -focus.y)
    }

    /// Page points (top left 0, 0) folded by `fold` to screen, in true
    /// perspective: the transform of a view laid out at the screen's
    /// origin in page points.
    func projection(_ fold: CATransform3D) -> CATransform3D {
        var t = fold
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(-StarPaper.width / 2 - focus.x,
                                                                -StarPaper.height / 2 - focus.y, 0))
        t = CATransform3DConcat(t, CATransform3DMakeScale(z, z, z))
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / focal
        t = CATransform3DConcat(t, perspective)
        return CATransform3DConcat(t, CATransform3DMakeTranslation(anchor.x, anchor.y, 0))
    }
}

// MARK: - Folds

/// How the page folds up onto its band: three mountain folds, each of
/// the rows beyond a crease turning away behind its neighbour, outer rows
/// first, alternating sides (the prototype's top pleat, bottom pleat,
/// then the pair). Their angles run on the prototype's three slots.
struct FoldPlan {
    struct Fold {
        let crease: CGFloat
        /// Rows above the band turn up and back; below, down and back.
        let above: Bool
        /// The rows this fold turns.
        let rows: ClosedRange<Int>
    }

    let folds: [Fold]
    /// The band's middle on the page.
    private let middle: CGFloat

    init(row band: Int) {
        middle = (CGFloat(band) + 0.5) * StarPaper.tile
        let tile = StarPaper.tile
        let above = (0..<band).map { j in Fold(crease: CGFloat(j + 1) * tile, above: true, rows: 0...j) }
        let below = (band + 1..<4).reversed().map { j in Fold(crease: CGFloat(j) * tile, above: false, rows: j...3) }
        var order: [Fold] = []
        var tops = above[...], bottoms = below[...]
        while let next = tops.popFirst() ?? bottoms.popFirst() {
            order.append(next)
            if let other = bottoms.popFirst() { order.append(other) }
        }
        folds = order
    }

    /// The order the folds open in (Open): those at the band's edges
    /// first, the later of two first, then outward, so a fold inside a
    /// folded packet never opens before the packet.
    var openOrder: [Int] {
        folds.indices.sorted { a, b in
            let da = distance(folds[a]), db = distance(folds[b])
            return da == db ? a > b : da < db
        }
    }

    private func distance(_ fold: Fold) -> CGFloat {
        abs(fold.crease - middle) - StarPaper.tile / 2
    }

    /// The fold turning `row` itself: the one at its inner edge.
    func own(_ row: Int) -> Int? {
        folds.firstIndex { $0.above ? $0.crease == CGFloat(row + 1) * StarPaper.tile
                                    : $0.crease == CGFloat(row) * StarPaper.tile }
    }

    /// Row `row` turned by every fold it is in, outermost crease first.
    func transform(of row: Int, angles: [CGFloat]) -> CATransform3D {
        var t = CATransform3DIdentity
        let turning = folds.indices.filter { folds[$0].rows.contains(row) }
            .sorted { abs(folds[$0].crease - middle) > abs(folds[$1].crease - middle) }
        for index in turning where angles[index] > 1e-3 {
            t = CATransform3DConcat(t, Self.hinge(folds[index].crease, angles[index], away: !folds[index].above))
        }
        return t
    }

    /// A mountain fold about the level line `y`: the paper beyond it
    /// turns `angle` away from the viewer.
    static func hinge(_ y: CGFloat, _ angle: CGFloat, away below: Bool) -> CATransform3D {
        let a = below ? angle : -angle
        var r = CATransform3DIdentity
        r.m22 = cos(a)
        r.m23 = -sin(a)
        r.m32 = sin(a)
        r.m33 = cos(a)
        return CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(0, -y, 0), r),
                                   CATransform3DMakeTranslation(0, y, 0))
    }
}
// swiftlint:enable identifier_name
