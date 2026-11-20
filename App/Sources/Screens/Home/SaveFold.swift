import MiraNoteKit
import SwiftUI

// Design X's timeline maths (proto.html, renderSave): t (ms) and p/q/u/v
// (progress) read as the formulas they are.
// swiftlint:disable identifier_name

/// The SAVE fold (#206, design X), over Home: the editor's page half-folds
/// on a 3D crease, folds up accordion-style onto its band into one strip,
/// the strip ties and winds five rolls while the camera pushes in, puffs
/// into a big matte paper star; the header jar steps out, its cap hops
/// aside, the star arcs into the open half of the mouth, bounces twice,
/// the cap seats and the jar docks back into its chip. Home stays sharp
/// under a light veil. 1.8 s. Only drawn: VoiceOver hears the landing.
/// Under Reduce Motion the page cross-fades to its star, which fades into
/// the header jar (0.5 s).
struct SaveFold: View {
    let paper: StarPaper
    /// The header jar chip's middle, in this view's space.
    let chip: CGPoint
    /// The foot of Home's ask bar: the knot, the star and its toss stay
    /// below it, clear of the headline, Start and the bar.
    let clear: CGFloat
    /// This month's stars, the new one among them (`newStar`) unless its
    /// page is dated another month: then it drops in out of sight.
    let pile: JarPile
    let newStar: Memory.ID
    let start: Date
    /// The editor's background, opening onto Home.
    let editorBackground: Color
    /// Home's background: the veil over it.
    let veilColor: Color
    let reduceMotion: Bool

    /// Where the editor shows its page's top: 42 pt below the safe area
    /// (measured in the editor, its nav row and gap).
    static var editorPageTop: CGFloat {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        return (window?.safeAreaInsets.top ?? 62) + 42
    }

    var body: some View {
        let editorTop = Self.editorPageTop, readingTop = OpenUnfold.readingTop
        return GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let t = CGFloat(StarClock.ms(since: start, at: timeline.date))
                let stage = Stage(size: proxy.size, chip: chip, editorTop: editorTop, readingTop: readingTop,
                                  clear: clear)
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        if reduceMotion {
                            drawFade(in: context, stage: stage, at: t)
                        } else {
                            drawBehind(in: context, stage: stage, at: t)
                        }
                    }
                    if !reduceMotion, t < CGFloat(StarFold.pleatsEnd) {
                        FoldPageView(paper: paper, plan: FoldPlan(row: paper.row), pose: pagePose(stage, at: t))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The prototype's 402 x 874 screen fitted to this one.
    struct Stage {
        let size: CGSize
        let chip: CGPoint
        /// Where the editor and reading mode show the page's top.
        let editorTop: CGFloat
        let readingTop: CGFloat
        /// What the star stays below (Home's ask bar); 0 for none.
        var clear: CGFloat = 0
        var k: CGFloat { size.width / 402 }
        /// The big star's reach, its 7% pop included.
        var heroReach: CGFloat { FoldDrawing.hero * k * 1.08 }
        /// The hero point: the page's resting middle, where it winds and
        /// puffs; never higher than its star clears `clear`.
        var hero: CGPoint {
            CGPoint(x: size.width / 2, y: max(size.height * 446 / 874, clear + 12 * k + heroReach))
        }
        /// Where the jar steps out to: low right, its cap below the star,
        /// its foot above the home indicator.
        var jar: CGPoint {
            let s = SaveFold.stageScale * k
            let below = hero.y + heroReach + 8 * k + 98 * s, lowest = size.height - 40 * k - 78 * s
            return CGPoint(x: size.width * 300 / 402, y: min(max(size.height * 628 / 874, below), lowest))
        }
        var pageScale: CGFloat { CanvasCard.pageScale(rowWidth: size.width) }
        var editorCenter: CGPoint {
            CGPoint(x: size.width / 2, y: editorTop + StarPaper.half * pageScale)
        }
    }

    // MARK: Page

    // swiftlint:disable:next large_tuple
    private func camera(_ stage: Stage, at t: CGFloat) -> (camera: FoldCamera, n: CGFloat, lift: CGFloat) {
        let nc = CGFloat(FoldDrawing.rolls) * Ease.sine(Ease.seg(t, 680, 1000)), n = FoldDrawing.step(nc)
        let lift = Ease.outBack(Ease.seg(t, 600, 700), 1.6)
        var zoom: CGFloat, fx: CGFloat = 0
        if t < 560 {
            zoom = Ease.lerp(1, 0.94, Ease.out3(Ease.seg(t, 0, 320)))
            let q = Ease.seg(t, 270, 420)
            if q > 0, q < 1 { zoom *= 1 - 0.014 * sin(.pi * q) * (1 - q) }
        } else {
            let w = Ease.inOut3(Ease.seg(t, 560, 650))
            zoom = Ease.lerp(0.94, FoldDrawing.fitZoom(nc), w)
            fx = Ease.lerp(FoldDrawing.fitX(nc) * w, FoldDrawing.knotX(n), Ease.inOut3(Ease.seg(t, 900, 1000)))
        }
        // From the editor's page to the hero point.
        let from = Ease.out3(Ease.seg(t, 0, 320))
        zoom *= Ease.lerp(stage.pageScale / stage.k, 1, from)
        let anchor = CGPoint(x: Ease.lerp(stage.editorCenter.x, stage.hero.x, from),
                             y: Ease.lerp(stage.editorCenter.y, stage.hero.y, from))
        let focus = CGPoint(x: fx, y: paper.bandY * Ease.inOut3(Ease.seg(t, 150, 560)) - 6 * min(1, lift))
        return (FoldCamera(zoom: zoom, focus: focus, anchor: anchor, scale: stage.k), n, lift)
    }

    private func pagePose(_ stage: Stage, at t: CGFloat) -> PagePose {
        let camera = camera(stage, at: t).camera
        if t < 280 {
            return PagePose(camera: camera, half: Ease.foldIn(t, 20, 270, 60), shadow: 1,
                            lift: Ease.out3(Ease.seg(t, 0, 260)), border: 1, tail: 1 - Ease.seg(t, 20, 90))
        }
        return PagePose(camera: camera, pleats: [Ease.foldIn(t, 280, 400, 40), Ease.foldIn(t, 330, 450, 40),
                                                 Ease.foldIn(t, 460, 580, 40)], shadow: 1)
    }

    // MARK: Jar, strip and star

    /// The header jar stepping out to its stage and back (jar units at
    /// `scale` points apiece, the foot at `foot`).
    private struct JarPose {
        var center: CGPoint
        var scale: CGFloat
        var rotation: CGFloat = 0
        var cap = JarArt.Cap()
        var glint: CGFloat = 0
        var rip: CGFloat = 0
        var caustic: CGFloat = 0
        var foot: CGPoint { CGPoint(x: center.x, y: center.y + 78 * scale) }

        func screen(_ p: CGPoint) -> CGPoint {
            let c = cos(rotation), s = sin(rotation)
            return CGPoint(x: center.x + scale * (p.x * c - p.y * s), y: foot.y + scale * (p.x * s + p.y * c))
        }
    }

    private static let chipScale = HeaderJar.unit
    private static let stageScale: CGFloat = 0.85

    private func jar(_ stage: Stage, at t: CGFloat) -> JarPose {
        let a = Ease.inOut3(Ease.seg(t, 900, 1200)), back = Ease.inOut3(Ease.seg(t, 1590, 1750))
        let out = CGPoint(x: Ease.lerp(stage.chip.x, stage.jar.x, a), y: Ease.lerp(stage.chip.y, stage.jar.y, a))
        let scale = Ease.lerp(Ease.lerp(Self.chipScale, Self.stageScale * stage.k, a), Self.chipScale, back)
        var pose = JarPose(center: CGPoint(x: Ease.lerp(out.x, stage.chip.x, back),
                                           y: Ease.lerp(out.y, stage.chip.y, back)), scale: scale)
        let bump = Ease.seg(t, 1750, 1800)
        if bump > 0, bump < 1 { pose.scale *= 1 + 0.1 * sin(.pi * bump) }
        let tau = t - 1440
        if tau > 0 { pose.rotation = 0.05 * exp(-tau / 200) * sin(2 * .pi * tau / 300) * (1 - back) }
        if t < 1460 {
            let po = Ease.seg(t, 1130, 1240)
            pose.cap = JarArt.Cap(ask: Ease.out3(po), y: -12 * sin(.pi * po), turn: 20 * po)
        } else {
            let pc = Ease.seg(t, 1460, 1580)
            pose.cap = JarArt.Cap(ask: 1 - Ease.bounceOut(pc), turn: 20 - 20 * pc)
        }
        pose.glint = t >= 1440 ? Ease.seg(t, 1440, 1740) : 0
        pose.rip = Ease.seg(t, 1440, 1720)
        pose.caustic = pose.rip > 0 && pose.rip < 1 ? sin(.pi * pose.rip) : 0
        return pose
    }

    private var landing: JarPile.Star? { pile.stars.first { $0.id == newStar } }

    // swiftlint:disable:next function_body_length
    private func drawBehind(in context: GraphicsContext, stage: Stage, at t: CGFloat) {
        let full = Path(CGRect(origin: .zero, size: stage.size))
        // Lighter than the prototype's 34%: Home's cards are darker than its
        // mock, and a stronger cream greys them. It lifts slowly, no pop.
        let veil = Ease.out3(Ease.seg(t, 80, 260)) * (1 - Ease.inOut3(Ease.seg(t, 1200, 1800)))
        if veil > 0 { context.fill(full, with: .color(veilColor.opacity(0.18 * veil))) }

        // The jar, the star landing in it, the cap.
        let pose = jar(stage, at: t)
        var jarContext = context
        jarContext.translateBy(x: pose.foot.x, y: pose.foot.y)
        jarContext.rotate(by: .radians(pose.rotation))
        jarContext.scaleBy(x: pose.scale, y: pose.scale)
        JarArt.back(in: jarContext, s: pose.scale, caustic: pose.caustic)
        let tau = t - 1440
        let push = tau > 0 ? 3 * (tau / 80) * exp(1 - tau / 80) : 0
        let landing = landing
        pile.draw(in: jarContext, except: newStar) { star in
            guard let landing, push > 0 else { return .zero }
            let dx = star.center.x - landing.center.x, dy = star.center.y - landing.center.y, d = hypot(dx, dy)
            guard d < 30, d > 0 else { return .zero }
            return CGSize(width: dx / d * push, height: dy / d * push)
        }
        if let landing, t >= 1440 {
            let hop = -9 * abs(sin(.pi * tau / 150)) * exp(-tau / 120)
            let wiggle = 0.2 * exp(-tau / 140) * sin(tau / 40)
            var inside = jarContext
            inside.clip(to: JarArt.body())
            let glow = 1 - Ease.seg(t, 1440, 1800)
            if glow > 0 {
                let r = landing.radius * 2.4
                inside.fill(Path(ellipseIn: CGRect(x: landing.center.x - r, y: landing.center.y + hop - r,
                                                   width: 2 * r, height: 2 * r)),
                            with: .radialGradient(Gradient(colors: [Color(.sRGB, red: 1, green: 206 / 255,
                                                                          blue: 150 / 255, opacity: 0.6 * glow),
                                                                    Color(.sRGB, red: 1, green: 206 / 255,
                                                                          blue: 150 / 255, opacity: 0)]),
                                                  center: CGPoint(x: landing.center.x, y: landing.center.y + hop),
                                                  startRadius: 0, endRadius: r))
            }
            FoldedStar.draw(in: inside, paper: paper, at: CGPoint(x: landing.center.x, y: landing.center.y + hop),
                            radius: landing.radius, rotation: landing.rotation + wiggle,
                            look: .init(k: landing.radius / FoldDrawing.knot, shadow: 0.5))
        }
        if t >= 1200, t < 1440 { toss(in: context, stage: stage, at: t, landing: landing) }
        JarArt.front(in: jarContext, s: pose.scale, glint: pose.glint, rip: pose.rip)
        JarArt.cap(in: jarContext, s: pose.scale, cap: pose.cap)

        // The editor's background opens onto Home.
        let editor = 1 - Ease.out3(Ease.seg(t, 90, 260))
        if editor > 0 { context.fill(full, with: .color(editorBackground.opacity(editor))) }

        let (camera, n, lift) = camera(stage, at: t)
        if t >= 600, t < 1000 {
            // The folded page is a strip now: it ties, then winds five rolls.
            var ctx = context
            camera.apply(to: &ctx)
            ctx.translateBy(x: 0, y: paper.bandY - 6 * lift)
            FoldDrawing(paper: paper).wind(in: ctx, n: n, tie: Ease.inOut3(Ease.seg(t, 610, 680)), lift: lift,
                                           ripple: 2.4 * sin(.pi * Ease.seg(t, 600, 950)), phase: t / 85)
        } else if t >= 1000, t < 1200 {
            // Squeeze, a spring puff, a 7% pop and a 14 degree twist.
            let squeeze = 1 - 0.05 * Ease.out3(Ease.seg(t, 1000, 1040)) * (1 - Ease.out3(Ease.seg(t, 1040, 1100)))
            let pop = 1 + 0.07 * sin(.pi * Ease.seg(t, 1040, 1180))
            let R = FoldDrawing.hero * squeeze * pop * stage.k
            FoldedStar.draw(in: context, paper: paper, at: stage.hero, radius: R,
                            rotation: FoldDrawing.wound + FoldDrawing.twist * Ease.out3(Ease.seg(t, 1040, 1195)),
                            look: .init(puff: Ease.spring(Ease.seg(t, 1040, 1190), 9),
                                        bands: FoldDrawing.bands(CGFloat(FoldDrawing.rolls)),
                                        k: R / FoldDrawing.knot, layers: CGFloat(FoldDrawing.rolls), shadow: 1))
        }
    }

    /// The star arcs into the open half of the mouth, then drops straight
    /// onto the pile, landing at its turn there (stars look alike every
    /// 72 degrees). With no place in this month's pile it fades as it drops.
    private func toss(in context: GraphicsContext, stage: Stage, at t: CGFloat, landing: JarPile.Star?) {
        let landed = jar(stage, at: StarFold.land)
        let radius = landing?.radius ?? pile.stars.first?.radius ?? 18
        let end = landed.screen(landing?.center ?? CGPoint(x: -24, y: -60))
        let mouth = landed.screen(CGPoint(x: -24, y: -150))
        let Rm = radius * landed.scale * 1.05, Re = radius * landed.scale
        let R0 = FoldDrawing.hero * stage.k
        let at: CGPoint, R: CGFloat
        if t < 1390 {
            let u = Ease.sine(Ease.seg(t, 1200, 1390))
            let control = CGPoint(x: mouth.x - 60 * stage.k,
                                  y: max(stage.clear + R0, min(stage.hero.y, mouth.y) - 60 * stage.k))
            at = Ease.bezier(stage.hero, control, mouth, u)
            R = R0 * pow(Rm / R0, u)
        } else {
            let v = Ease.in2(Ease.seg(t, 1390, 1440))
            at = CGPoint(x: Ease.lerp(mouth.x, end.x, v), y: Ease.lerp(mouth.y, end.y, v))
            R = Ease.lerp(Rm, Re, v)
        }
        let from = FoldDrawing.wound + FoldDrawing.twist, fifth = 2 * CGFloat.pi / 5
        let miss = (landing?.rotation ?? from + FoldDrawing.spin) - from - FoldDrawing.spin
        let spin = FoldDrawing.spin + miss - fifth * (miss / fifth).rounded()
        FoldedStar.draw(in: context, paper: paper, at: at, radius: R,
                        rotation: from + spin * Ease.out3(Ease.seg(t, 1200, 1440)),
                        look: .init(k: R / FoldDrawing.knot, shadow: Ease.lerp(1, 0.5, Ease.seg(t, 1200, 1440)),
                                    opacity: landing == nil ? 1 - Ease.seg(t, 1390, 1440) : 1))
    }

    // MARK: Reduce Motion

    /// The page cross-fades to its finished star (200 ms), which fades and
    /// shrinks into the header jar where it is (300 ms).
    private func drawFade(in context: GraphicsContext, stage: Stage, at t: CGFloat) {
        let fade = CGFloat(StarFold.fadeToStar), end = CGFloat(StarFold.fadeEnd)
        // The header jar, which the fold hides, with the stars it had.
        var jarContext = context
        jarContext.translateBy(x: stage.chip.x, y: stage.chip.y + 78 * Self.chipScale)
        jarContext.scaleBy(x: Self.chipScale, y: Self.chipScale)
        JarArt.back(in: jarContext, s: Self.chipScale)
        pile.draw(in: jarContext, except: newStar)
        JarArt.front(in: jarContext, s: Self.chipScale)
        JarArt.cap(in: jarContext, s: Self.chipScale)
        let page = 1 - Ease.seg(t, 0, fade)
        if page > 0 {
            context.fill(Path(CGRect(origin: .zero, size: stage.size)), with: .color(editorBackground.opacity(page)))
            var ctx = context
            ctx.opacity *= page
            let s = stage.pageScale
            let rect = CGRect(x: (stage.size.width - StarPaper.width * s) / 2, y: stage.editorTop,
                              width: StarPaper.width * s, height: StarPaper.height * s)
            ctx.clip(to: Path(roundedRect: rect, cornerRadius: StarPaper.corner * s))
            ctx.draw(paper.page,
                     in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: paper.fullHeight * s))
        }
        let shrink = Ease.seg(t, fade, end)
        let at = CGPoint(x: Ease.lerp(stage.hero.x, stage.chip.x, shrink),
                         y: Ease.lerp(stage.hero.y, stage.chip.y, shrink))
        let R = Ease.lerp(FoldDrawing.hero * stage.k, 4, shrink)
        FoldedStar.draw(in: context, paper: paper, at: at, radius: R, rotation: 0,
                        look: .init(k: R / FoldDrawing.knot, shadow: 1 - shrink,
                                    opacity: Ease.seg(t, 0, fade) * (1 - shrink)))
    }
}
// swiftlint:enable identifier_name
