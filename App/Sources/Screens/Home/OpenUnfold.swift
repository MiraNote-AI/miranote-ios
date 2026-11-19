import MiraNoteKit
import SwiftUI

// The fold demo's timeline maths: t (ms), p/u/f/a/e/m (progress), k
// (arm) and E (its easings) read as the formulas they are.
// swiftlint:disable identifier_name

/// The OPEN unfold (#206, fold demo v4), drawn over the fading jar after
/// a hold commits: the star pops and rises to the middle, turns back into
/// its knot, the knot unwinds the strip, tilting it to its cut, the strip
/// docks onto a faint page at its true place, and the page unrolls from
/// it. Then the page itself opens (`pageFrame`, the zoom's source).
struct OpenUnfold: View {
    let paper: StarPaper
    /// The held star: its middle in this view's space, its radius as held
    /// and its turn in degrees.
    let from: CGPoint
    let radius: CGFloat
    let rotation: Double
    let start: Date
    /// Under Reduce Motion the page only fades in where reading shows it.
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = CGFloat(timeline.date.timeIntervalSince(start) * 1000)
                if reduceMotion {
                    let fold = FoldDrawing(paper: paper, unit: CanvasCard.pageScale(rowWidth: size.width))
                    let frame = Self.readingFrame(fold, size: size)
                    fold.page(in: context, center: CGPoint(x: frame.midX, y: frame.midY), scale: 1, corner: 0,
                              opacity: Ease.seg(t, 0, CGFloat(StarUnfold.fade)))
                } else {
                    draw(in: context, size: size, at: t)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the page lies when it has unrolled: the open's source.
    static func pageFrame(_ paper: StarPaper, size: CGSize) -> CGRect {
        let fold = FoldDrawing(paper: paper, unit: CanvasCard.pageScale(rowWidth: size.width))
        let page = fold.pageSize(FoldDrawing.stage)
        return CGRect(x: size.width / 2 - page.width / 2, y: size.height * 0.487 - page.height / 2,
                      width: page.width, height: page.height)
    }

    /// Where reading mode shows the page's top: below its header row.
    static func readingFrame(_ fold: FoldDrawing, size: CGSize) -> CGRect {
        let page = fold.pageSize(1)
        return CGRect(x: (size.width - page.width) / 2, y: readingTop, width: page.width, height: page.height)
    }

    /// The safe area's top plus reading mode's header (50 pt) and its 6 pt.
    static var readingTop: CGFloat {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        return (window?.safeAreaInsets.top ?? 59) + 56
    }

    // swiftlint:disable:next function_body_length
    private func draw(in context: GraphicsContext, size: CGSize, at t: CGFloat) {
        // swiftlint:disable:next type_name
        typealias E = Ease
        let fold = FoldDrawing(paper: paper, unit: CanvasCard.pageScale(rowWidth: size.width))
        let stage = FoldDrawing.stage
        let middle = CGPoint(x: size.width / 2, y: size.height * 0.434)
        let pageFrame = Self.pageFrame(paper, size: size)
        let pageCenter = CGPoint(x: pageFrame.midX, y: pageFrame.midY)
        let knot = fold.knotRadius
        let beat = StarUnfold.beat(at: Double(t))
        // From here the page itself (`pageFrame`) opens.
        guard beat != .open else { return }

        if beat == .rise {
            // The commit's pop, then the rise to hero size and back to the knot.
            let pop = E.keyframes(t, [(0, 1, nil), (60, 1.42 / 1.3, E.outC), (120, 1.36 / 1.3, E.sine)])
            let rise = E.bezier(0.3, 0, 0.1, 1, E.seg(t, 0, 210))
            let step = 72.0
            let resting = CGFloat((rotation - (rotation / step).rounded() * step) * .pi / 180)
            let inner = (0..<5).map { k in
                E.lerp(0.66, 0.809, E.inOut(E.seg(t, 130 + 15 * CGFloat(k), 170 + 15 * CGFloat(k))))
            }
            ring(in: context, at: from, radius: radius * 1.5 * pop, opacity: 1 - E.seg(t, 0, 70))
            PaperStar.draw(
                in: context, at: CGPoint(x: E.lerp(from.x, middle.x, rise), y: E.lerp(from.y, middle.y, rise)),
                radius: E.lerp(E.lerp(radius * pop, FoldDrawing.hero, rise), knot, E.seg(t, 170, 210)),
                inner: inner, rotation: E.lerp(resting, 0, rise), paint: paper.paint,
                style: .init(shadow: 1, hero: true, puff: E.lerp(1, 0, E.seg(t, 130, 210)))
            )
            let knotIn = E.seg(t, 170, 210)
            if knotIn > 0 {
                var ctx = context
                ctx.opacity *= knotIn
                ctx.translateBy(x: middle.x, y: middle.y)
                fold.knotFace(in: ctx, radius: knot, rotation: 0, wraps: CGFloat(FoldDrawing.wraps), shadow: 0)
            }
            return
        }
        if beat == .unwind {
            // The strip tilts to its cut while it unwinds.
            let u = E.seg(t, 210, 470), f = 1 - (0.5 * E.sine(u) + 0.5 * u)
            var ctx = context
            ctx.translateBy(x: middle.x, y: middle.y)
            ctx.rotate(by: .radians(paper.cutAngle * E.sine(E.seg(t, 290, 470))))
            ctx.translateBy(x: -middle.x, y: -middle.y)
            fold.wind(in: ctx, mid: middle, f: f)
            return
        }
        // A faint page under the strip, so it docks onto the page.
        fold.pageGhost(in: context, center: pageCenter, scale: stage, corner: 18,
                       opacity: 0.5 * E.sine(E.seg(t, 470, 550)) * (1 - E.seg(t, 650, 770)))
        if t >= 630 {
            // The page unrolls from the docked strip.
            let unroll = E.sine(E.seg(t, 630, 770))
            fold.page(in: context, center: pageCenter, scale: stage, corner: 18,
                      marks: .init(mask: E.lerp(paper.stripThickness / 2, paper.pageSize.height * 1.2, unroll)))
        }
        let lay = E.inOut(E.seg(t, 470, 630))
        let dock = fold.band(pageCenter: pageCenter, scale: stage)
        fold.strip(in: context,
                   at: CGPoint(x: E.lerp(middle.x, dock.center.x, lay), y: E.lerp(middle.y, dock.center.y, lay)),
                   angle: paper.cutAngle, scale: E.lerp(stage * fold.unit, dock.scale, lay),
                   lift: 1 - E.seg(t, 550, 650), opacity: 1 - E.seg(t, 630, 680))
    }

    /// The hold's ring, as `StarButton` drew it full.
    private func ring(in context: GraphicsContext, at center: CGPoint, radius: CGFloat, opacity: CGFloat) {
        guard opacity > 0 else { return }
        var ctx = context
        ctx.opacity *= opacity
        let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: 2 * radius, height: 2 * radius))
        ctx.stroke(circle, with: .color(.white.opacity(0.7)), lineWidth: 5)
        ctx.stroke(circle, with: .color(Color(hex: 0xA8682A).opacity(0.95)), lineWidth: 3)
    }
}
// swiftlint:enable identifier_name
