import MiraNoteKit
import SwiftUI

// The fold demo's timeline maths: t (ms), p/u/f/a/e/m (progress), k
// (arm) and E (its easings) read as the formulas they are.
// swiftlint:disable identifier_name

/// The SAVE fold (#206, fold demo v4), drawn over Home: the page shrinks
/// off the editor, its strip is cut and lifts, winds into a pentagon knot,
/// is pinched and puffed into a star and thrown into the header jar. Home
/// dims while it folds; the jar circle stays lit. About 1.3 s, then the
/// jar's own landing. Only drawn: VoiceOver hears the landing.
struct SaveFold: View {
    let paper: StarPaper
    /// The header jar circle's middle, in this view's space.
    let jar: CGPoint
    let start: Date
    /// The editor's background, fading off at the start.
    let editorBackground: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = CGFloat(timeline.date.timeIntervalSince(start) * 1000)
                draw(in: context, size: size, at: t)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func draw(in context: GraphicsContext, size: CGSize, at t: CGFloat) {
        // swiftlint:disable:next type_name
        typealias E = Ease
        let fold = FoldDrawing(paper: paper, unit: CanvasCard.pageScale(rowWidth: size.width))
        let stage = FoldDrawing.stage
        let middle = CGPoint(x: size.width / 2, y: size.height * 0.5)
        let ink = Color(.sRGB, red: 40 / 255, green: 30 / 255, blue: 20 / 255)

        // Home dims under the fold, all but the jar circle.
        let dim = E.seg(t, 120, 200) * (1 - E.sine(E.seg(t, 960, 1260)))
        let scrim = max(0.18 * (1 - E.outC(E.seg(t, 0, 300))), 0.16 * dim)
        if scrim > 0 {
            var veil = Path(CGRect(origin: .zero, size: size))
            veil.addPath(Path(ellipseIn: CGRect(x: jar.x - 24, y: jar.y - 24, width: 48, height: 48)))
            context.fill(veil, with: .color(ink.opacity(scrim)), style: FillStyle(eoFill: true))
        }
        let local = E.seg(t, 330, 400) * (1 - E.seg(t, 880, 960))
        if local > 0 {
            context.fill(Path(CGRect(x: middle.x - 160, y: middle.y - 160, width: 320, height: 320)),
                         with: .radialGradient(Gradient(colors: [ink.opacity(0.18 * local), ink.opacity(0)]),
                                               center: middle, startRadius: 0, endRadius: 160))
        }
        let editor = 1 - E.seg(t, 0, 200)
        if editor > 0 {
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(editorBackground.opacity(editor)))
        }

        let pageHeight = fold.pageSize(1).height
        let from = CGPoint(x: middle.x, y: Self.editorPageTop + pageHeight / 2)
        // The pinch (780-920) overlaps the throw (880-1320).
        let inner = (0..<5).map { k in
            E.lerp(0.809, 0.6, E.inOut(E.seg(t, 780 + 20 * CGFloat(k), 840 + 20 * CGFloat(k))))
        }
        let pinch = E.keyframes(t, [(780, 1, nil), (825, 0.88, E.inQ), (880, 1.08, E.outC), (920, 1, E.sine)])
        let knot = fold.knotRadius, hero = FoldDrawing.hero

        switch StarFold.beat(at: Double(t)) {
        case .shrink:
            let p = E.spring(E.seg(t, 0, 180), 0.6)
            fold.page(in: context, center: CGPoint(x: middle.x, y: E.lerp(from.y, middle.y, p)),
                      scale: E.lerp(1, stage, p), corner: E.lerp(Metrics.canvasCorner, 18, p),
                      shadow: E.lerp(0.4, 1, E.seg(t, 0, 180)))
        case .cut:
            // The page recedes, its strip lifts, holds, and turns level.
            let recede = E.outC(E.seg(t, 180, 400)), scale = E.lerp(stage, 0.57, recede)
            let center = CGPoint(x: middle.x, y: middle.y + 6 * recede)
            let shown = 1 - E.inQ(E.seg(t, 270, 400))
            fold.page(in: context, center: center, scale: scale, corner: 18, opacity: shown, shadow: shown,
                      marks: .init(slot: E.sine(E.seg(t, 190, 250)),
                                   score: E.seg(t, 180, 225) + (t > 225 ? E.seg(t, 225, 260) * 0.2 : 0)))
            let lift = E.outC(E.seg(t, 180, 250)), move = E.inOut(E.seg(t, 290, 400))
            let band = fold.band(pageCenter: center, scale: scale)
            let grow = E.lerp(1, 1.12, lift) * E.lerp(1, 1 / 1.12, move)
            fold.strip(in: context,
                       at: CGPoint(x: E.lerp(band.center.x, middle.x, move), y: E.lerp(band.center.y, middle.y, move)),
                       angle: E.lerp(band.angle, 0, move), scale: E.lerp(band.scale, stage * fold.unit, move) * grow,
                       lift: lift, sheen: E.seg(t, 190, 360))
        case .wind:
            // Half sine, half linear: the wind leaves rest at once.
            let u = E.seg(t, 400, 780)
            fold.wind(in: context, mid: middle, f: 0.5 * E.sine(u) + 0.5 * u)
        case .pinch:
            PaperStar.draw(in: context, at: middle, radius: E.lerp(knot, hero, E.outC(E.seg(t, 780, 880))) * pinch,
                           inner: inner, rotation: 0, paint: paper.paint, style: .init(shadow: 1, hero: true))
            let knotFade = 1 - E.seg(t, 780, 830)
            if knotFade > 0 {
                var ctx = context
                ctx.opacity *= knotFade
                ctx.translateBy(x: middle.x, y: middle.y)
                ctx.scaleBy(x: pinch, y: pinch)
                fold.knotFace(in: ctx, radius: knot, rotation: 0, wraps: CGFloat(FoldDrawing.wraps), shadow: 0)
            }
        case .throw:
            // An arc that crests above the jar and drops in, spinning to rest.
            let a = E.seg(t, StarFold.throwStart, StarFold.land)
            let e = pow(a, 1.6), m = 1 - e
            let crest = CGPoint(x: size.width * 0.744, y: jar.y - 84)
            let at = CGPoint(x: m * m * middle.x + 2 * m * e * crest.x + e * e * jar.x,
                             y: m * m * middle.y + 2 * m * e * crest.y + e * e * jar.y)
            let shadow = a < 0.8 ? E.lerp(1, 0.5, a / 0.8) : 0.5 * (1 - (a - 0.8) / 0.2)
            PaperStar.draw(in: context, at: at, radius: E.lerp(hero * pinch, Self.landed, E.inQ(a)),
                           inner: a < 0.5 ? inner : PaperStar.rest, rotation: E.outC(a) * Self.spin,
                           paint: paper.paint, style: .init(shadow: shadow, hero: a < 0.5, puff: E.lerp(1, 0.6, a)))
        case .landed:
            // The newest star rests over the jar circle while it rings,
            // then goes in.
            PaperStar.draw(in: context, at: jar, radius: Self.landed, inner: PaperStar.rest, rotation: Self.spin,
                           paint: paper.paint,
                           style: .init(puff: 0.6, opacity: 1 - E.seg(t, 1480, CGFloat(StarFold.end))))
        case .done:
            break
        }
    }

    /// The star's radius in the jar circle.
    private static let landed: CGFloat = 5.5

    /// The throw's turn: three points round, so it lands upright.
    private static let spin: CGFloat = 3 * 72 * .pi / 180

    /// Where the editor's page card starts, from the screen's top: below
    /// the status bar and the editor's nav row.
    static let editorPageTop: CGFloat = 120
}
// swiftlint:enable identifier_name
