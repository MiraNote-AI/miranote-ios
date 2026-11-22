import MiraNoteKit
import SwiftUI

// Design X's timeline maths (proto.html, renderOpen): c (ms from the
// commit) and p/q/u/g/w (progress) read as the formulas they are.
// swiftlint:disable identifier_name

/// The OPEN unfold (#206, design X), over the jar after a hold commits:
/// the ring releases, the cap unscrews and lifts away, the star rises out
/// of the mouth to hero size, relaxes into its knot, unwinds into the
/// folded strip, the pleats swing out and the half with the title and
/// text unfolds last, and the page grows into the reading page, where
/// reading mode takes over (1.4 s). Under Reduce Motion the star cross-
/// fades to the reading page (0.4 s).
struct OpenUnfold: View {
    let paper: StarPaper
    /// The held star: its middle in this view's space, its radius as held
    /// and its turn in degrees.
    let from: CGPoint
    let radius: CGFloat
    let rotation: Double
    /// The jar's frame in this view's space: its cap comes off.
    let jar: CGRect
    let start: Date
    let reduceMotion: Bool

    var body: some View {
        let readingTop = Self.readingTop
        return GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                // Held at its last frame until reading mode is up.
                let c = min(CGFloat(StarClock.ms(since: start, at: timeline.date)), CGFloat(StarUnfold.end) - 1)
                let stage = SaveFold.Stage(size: proxy.size, chip: .zero, editorTop: 0, readingTop: readingTop)
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        if reduceMotion {
                            drawFade(in: context, stage: stage, at: c)
                        } else {
                            draw(in: context, stage: stage, at: c)
                        }
                    }
                    if !reduceMotion, let pose = pagePose(stage, at: c) {
                        FoldPageView(paper: paper, plan: FoldPlan(row: paper.row), pose: pose)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where reading mode shows the page's top: below its 58 pt header
    /// row and its 6 pt gap (measured in reading mode).
    static var readingTop: CGFloat {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        return (window?.safeAreaInsets.top ?? 62) + 64
    }

    /// The open's hero point: above the jar's top, as far as the
    /// prototype has it (66 pt), and never lower than it does.
    private func hero(_ stage: SaveFold.Stage) -> CGPoint {
        let above = jar.width > 0 ? jar.minY - 66 * stage.k : .infinity
        return CGPoint(x: stage.size.width / 2, y: min(stage.size.height * 262 / 874, above))
    }

    // MARK: Page

    private func pagePose(_ stage: SaveFold.Stage, at c: CGFloat) -> PagePose? {
        guard c >= 840, c < CGFloat(StarUnfold.end) else { return nil }
        let creases = 0.8 * (1 - Ease.inOut3(Ease.seg(c, 1060, 1300)))
        if c >= 1140 {
            // The card grows into the reading page; the page's own paper
            // carries on down to the screen's foot.
            let g = Ease.inOut3(Ease.seg(c, 1140, 1390)), e = Ease.inOut3(Ease.seg(c, 1160, 1390))
            let reading = stage.pageScale, top = stage.readingTop
            let camera = FoldCamera(
                zoom: Ease.lerp(1, reading / stage.k, g), focus: .zero,
                anchor: CGPoint(x: stage.hero.x, y: Ease.lerp(stage.hero.y, top + StarPaper.half * reading, g)),
                scale: stage.k)
            return PagePose(camera: camera, shadow: 1 - g, border: 1 - g, creases: creases,
                            halfCrease: 0.8 * (1 - Ease.inOut3(Ease.seg(c, 1140, 1320))),
                            rows: Ease.lerp(StarPaper.height, paper.fullHeight, e),
                            corner: StarPaper.corner * (1 - e))
        }
        let camera = camera(stage, at: c).camera
        if c < 1000 {
            // The pleats swing back out of the strip, inner first.
            let windows: [(CGFloat, CGFloat)] = [(840, 930), (860, 950), (920, 1000)]
            var angles = [CGFloat](repeating: 0, count: 3)
            for (slot, fold) in FoldPlan(row: paper.row).openOrder.enumerated() {
                angles[fold] = .pi * (1 - Ease.springZ(Ease.seg(c, windows[slot].0, windows[slot].1), 0.78, 9))
            }
            return PagePose(camera: camera, pleats: angles,
                            shadow: Ease.out3(Ease.seg(c, 840, 900)), creases: creases)
        }
        // The half with the title and text swings out from behind.
        return PagePose(camera: camera, half: .pi * (1 - Ease.springZ(Ease.seg(c, 990, 1140), 0.78, 9)), shadow: 1,
                        border: 1, creases: creases)
    }

    // swiftlint:disable:next large_tuple
    private func camera(_ stage: SaveFold.Stage, at c: CGFloat) -> (camera: FoldCamera, n: CGFloat, lift: CGFloat) {
        let nc = CGFloat(FoldDrawing.rolls) * (1 - Ease.sine(Ease.seg(c, 500, 770))), n = FoldDrawing.step(nc)
        let lift = 1 - Ease.inOut3(Ease.seg(c, 780, 840))
        let w1 = Ease.inOut3(Ease.seg(c, 490, 600)), w2 = Ease.inOut3(Ease.seg(c, 830, 1140))
        let an = Ease.inOut3(Ease.seg(c, 490, 800))
        let zoom = Ease.lerp(Ease.lerp(FoldDrawing.heroZoom, FoldDrawing.fitZoom(nc), w1), 1, w2)
        let fx = Ease.lerp(Ease.lerp(FoldDrawing.knotX(n), FoldDrawing.fitX(nc), w1), 0, w2)
        let top = hero(stage)
        return (FoldCamera(zoom: zoom, focus: CGPoint(x: fx, y: Ease.lerp(paper.bandY, 0, w2) - 6 * lift),
                           anchor: CGPoint(x: Ease.lerp(top.x, stage.hero.x, an),
                                           y: Ease.lerp(top.y, stage.hero.y, an)),
                           scale: stage.k), n, lift)
    }

    // MARK: Ring, cap, star, knot and strip

    private func draw(in context: GraphicsContext, stage: SaveFold.Stage, at c: CGFloat) {
        let R0 = FoldDrawing.hero * stage.k, top = hero(stage)
        let held = CGFloat(rotation * .pi / 180)
        if c < 170 {
            // The ring releases outward.
            let p = Ease.seg(c, 0, 170), r = radius * 1.6 + 16 * Ease.out3(p)
            context.stroke(Path(ellipseIn: CGRect(x: from.x - r, y: from.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(StarButton.ring.opacity(0.9 * (1 - p))), lineWidth: 3 * (1 - p) + 0.5)
        }
        cap(in: context, at: c)
        if c < 150 {
            let press = Ease.lerp(0.93, 1, Ease.out3(Ease.seg(c, 0, 120)))
            FoldedStar.draw(in: context, paper: paper, at: from, radius: radius * press, rotation: held,
                            look: .init(k: radius / FoldDrawing.knot, shadow: 0.5))
        } else if c < 400 {
            // Straight up out of the mouth, growing to hero size.
            let u = Ease.seg(c, 150, 400)
            let at = Ease.bezier(from, CGPoint(x: stage.size.width / 2, y: top.y + 68 * stage.k), top, Ease.out3(u))
            let R1 = radius * 0.93, R = R1 * pow(R0 / R1, Ease.outBack(u, 1.1))
            FoldedStar.draw(in: context, paper: paper, at: at, radius: R,
                            rotation: Ease.lerp(held, FoldDrawing.wound + FoldDrawing.twist + 2 * .pi, Ease.out3(u)),
                            look: .init(k: R / FoldDrawing.knot, shadow: 0.8))
        } else if c < 490 {
            // It relaxes back into the knot, big and close.
            let q = Ease.seg(c, 400, 490), R = R0 * (1 + 0.05 * sin(.pi * q))
            FoldedStar.draw(in: context, paper: paper, at: top, radius: R,
                            rotation: FoldDrawing.wound + FoldDrawing.twist * (1 - Ease.inOut3(q)),
                            look: .init(puff: 1 - Ease.inOut3(q), bands: FoldDrawing.bands(CGFloat(FoldDrawing.rolls)),
                                        k: R / FoldDrawing.knot, layers: CGFloat(FoldDrawing.rolls), shadow: 1))
        } else if c < 840 {
            // The knot rolls back out into the strip: the folded page.
            let (camera, n, lift) = camera(stage, at: c)
            var ctx = context
            camera.apply(to: &ctx)
            ctx.translateBy(x: 0, y: paper.bandY - 6 * lift)
            FoldDrawing(paper: paper).wind(in: ctx, n: n, tie: 1 - Ease.inOut3(Ease.seg(c, 770, 830)), lift: lift,
                                           ripple: 2 * sin(.pi * Ease.seg(c, 500, 840)), phase: c / 85)
        }
    }

    /// The cap unscrews (a turn and 10 units up), then lifts away up and
    /// to the right, fading.
    private func cap(in context: GraphicsContext, at c: CGFloat) {
        guard c < 230, jar.width > 0 else { return }
        let unit = jar.width / 124
        let up = Ease.out3(Ease.seg(c, 0, 110)), off = Ease.inOut3(Ease.seg(c, 90, 220))
        var ctx = context
        ctx.translateBy(x: jar.midX, y: jar.maxY)
        ctx.scaleBy(x: unit, y: unit)
        JarArt.cap(in: ctx, s: unit, cap: JarArt.Cap(x: 50 * off, y: -10 * up - 40 * off,
                                                     rotation: 14 * .pi / 180 * off,
                                                     turn: 18 * up, opacity: 1 - off))
    }

    // MARK: Reduce Motion

    /// The star cross-fades to the reading page.
    private func drawFade(in context: GraphicsContext, stage: SaveFold.Stage, at c: CGFloat) {
        let p = Ease.seg(c, 0, CGFloat(StarUnfold.fade))
        FoldedStar.draw(in: context, paper: paper, at: from, radius: radius, rotation: CGFloat(rotation * .pi / 180),
                        look: .init(k: radius / FoldDrawing.knot, opacity: 1 - p))
        var page = context
        page.opacity *= p
        let s = stage.pageScale
        page.draw(paper.page, in: CGRect(x: (stage.size.width - StarPaper.width * s) / 2, y: stage.readingTop,
                                         width: StarPaper.width * s, height: paper.fullHeight * s))
    }
}
// swiftlint:enable identifier_name
