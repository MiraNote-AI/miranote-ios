import MiraNoteKit
import SwiftUI

// A port of the fold demo's canvas maths: t (ms), p/u/f (progress), R
// (radius), k (arm) read as the formulas they are; longer names would
// hide them. The drawing is one long struct, as the demo's file is.
// swiftlint:disable file_length
// swiftlint:disable identifier_name

/// A page ready to fold into its star, or to unfold from it (#206): its
/// top as a picture, where its strip was cut, the strip, and the star's
/// paint. Lengths are page points (the 360 pt page).
struct StarPaper {
    let page: Image
    let pageSize: CGSize
    /// The strip's middle on the page, its turn (y down) and its size.
    let cutCenter: CGPoint
    let cutAngle: CGFloat
    let stripLength: CGFloat
    let stripThickness: CGFloat
    let strip: Image
    let paint: StarPaint
    /// The page's soft shadow, drawn once: `shadowMargin` round the page.
    let pageShadow: Image
    static let shadowMargin: CGFloat = 60
}

/// The demo's easing curves (fold demo v4).
enum Ease {
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    static func clamp(_ x: CGFloat, _ a: CGFloat = 0, _ b: CGFloat = 1) -> CGFloat { max(a, min(b, x)) }
    /// Where `t` stands between `a` and `b`, 0...1.
    static func seg(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { clamp((t - a) / (b - a)) }
    static func inOut(_ p: CGFloat) -> CGFloat { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
    static func sine(_ p: CGFloat) -> CGFloat { 0.5 - 0.5 * cos(.pi * p) }
    static func outC(_ p: CGFloat) -> CGFloat { 1 - pow(1 - p, 3) }
    static func inQ(_ p: CGFloat) -> CGFloat { p * p }
    static func spring(_ p: CGFloat, _ overshoot: CGFloat) -> CGFloat {
        let q = p - 1
        return 1 + (overshoot + 1) * q * q * q + overshoot * q * q
    }

    /// A CSS cubic-bezier.
    static func bezier(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat) -> CGFloat {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var t = x
        for _ in 0..<8 {
            let xt = 3 * x1 * t * (1 - t) * (1 - t) + 3 * x2 * t * t * (1 - t) + t * t * t - x
            let d = 3 * x1 * (1 - t) * (1 - t) + 6 * (x2 - x1) * t * (1 - t) + 3 * (1 - x2) * t * t
            if abs(d) < 1e-6 { break }
            t = clamp(t - xt / d)
        }
        return 3 * y1 * t * (1 - t) * (1 - t) + 3 * y2 * t * t * (1 - t) + t * t * t
    }

    // swiftlint:disable:next large_tuple
    typealias Key = (CGFloat, CGFloat, ((CGFloat) -> CGFloat)?)

    /// Keyframes `(t, value)`, eased by `ease` between them (sine if nil).
    static func keyframes(_ t: CGFloat, _ keys: [Key]) -> CGFloat {
        guard let first = keys.first, t > first.0 else { return keys.first?.1 ?? 0 }
        for index in 1..<keys.count where t <= keys[index].0 {
            let from = keys[index - 1], to = keys[index]
            return lerp(from.1, to.1, (to.2 ?? sine)((t - from.0) / (to.0 - from.0)))
        }
        return keys[keys.count - 1].1
    }
}

/// The fold's drawings, ported from the demo: one strip renderer for the
/// cut, the wind and the lay-back; the pentagon knot; the page.
struct FoldDrawing { // swiftlint:disable:this type_body_length
    let paper: StarPaper
    /// Screen points per page point with the page at full size.
    let unit: CGFloat
    /// The page's scale on stage.
    static let stage = CGFloat(StarFold.pageScale)
    /// The hero star's radius at the pinch, the throw's start and the open.
    static let hero: CGFloat = 42
    static let wraps = 4

    private var length: CGFloat { paper.stripLength }
    private var thickness: CGFloat { paper.stripThickness }
    /// The strip's thickness on stage, in screen points.
    var stageThickness: CGFloat { thickness * Self.stage * unit }
    /// The knot's (and resting star's) radius on stage.
    var knotRadius: CGFloat { min(34, stageThickness * 1.0) }

    // MARK: Strip

    // swiftlint:disable:next large_tuple
    private typealias Hair = (u: CGFloat, bottom: Bool, length: CGFloat, angle: CGFloat)
    // swiftlint:disable:next large_tuple
    private typealias Edge = (top: [CGFloat], bottom: [CGFloat], hairs: [Hair])

    /// The fibre edge: smoothed noise along both sides, and hairlines.
    private static let edge: Edge = {
        var random = SeededRandom(77)
        var raw: [[CGFloat]] = [[], []]
        for side in 0..<2 { for _ in 0...edgeSteps { raw[side].append(random.next() - 0.5) } }
        let smooth = raw.map { values in
            values.indices.map { index in
                (values[max(0, index - 1)] + 2 * values[index] + values[min(edgeSteps, index + 1)]) / 4 * 1.4
            }
        }
        let hairs = (0..<16).map { index in
            (u: random.next(), bottom: index % 2 == 1, length: 1 + random.next() * 1.6,
             angle: (random.next() - 0.5) * 1.2)
        }
        return (smooth[0], smooth[1], hairs)
    }()
    private static let edgeSteps = 160

    /// The strip from `u0` (0...1 along it) to its end, centered at the
    /// origin, length along x.
    func ribbonPath(from u0: CGFloat) -> Path {
        let steps = Self.edgeSteps, rough = thickness / 46
        let first = Int(u0 * CGFloat(steps))
        var path = Path()
        path.move(to: CGPoint(x: -length / 2 + u0 * length, y: -thickness / 2 + Self.edge.top[first] * rough))
        for index in (first + 1)...steps {
            path.addLine(to: CGPoint(x: -length / 2 + length * CGFloat(index) / CGFloat(steps),
                                     y: -thickness / 2 + Self.edge.top[index] * rough))
        }
        for index in stride(from: steps, through: first + 1, by: -1) {
            path.addLine(to: CGPoint(x: -length / 2 + length * CGFloat(index) / CGFloat(steps),
                                     y: thickness / 2 + Self.edge.bottom[index] * rough))
        }
        path.addLine(to: CGPoint(x: -length / 2 + u0 * length, y: thickness / 2 + Self.edge.bottom[first] * rough))
        path.closeSubpath()
        return path
    }

    /// The strip in its own frame (page points): its picture with a soft
    /// light, a curl at its end, a lift shadow and a fibre edge.
    func ribbon(in context: GraphicsContext, from u0: CGFloat = 0, lift: CGFloat = 1, opacity: CGFloat = 1,
                sheen: CGFloat? = nil) {
        guard u0 < 0.999, opacity > 0 else { return }
        var ctx = context
        ctx.opacity *= opacity
        let shape = ribbonPath(from: u0)
        if lift > 0 {
            var shadow = ctx
            shadow.opacity *= lift
            shadow.addFilter(.shadow(color: Color(.sRGB, red: 40 / 255, green: 28 / 255, blue: 16 / 255,
                                                  opacity: Ease.lerp(0.3, 0.18, lift)),
                                     radius: Ease.lerp(4, 16, lift) / 2,
                                     x: Ease.lerp(0.5, 3, lift), y: Ease.lerp(1, 9, lift)))
            shadow.fill(shape, with: .color(Color(hex: 0xF0E8DA)))
        }
        var face = ctx
        face.clip(to: shape)
        let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
        face.draw(paper.strip, in: rect)
        face.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.12), location: 0),
                             .init(color: .white.opacity(0), location: 0.5),
                             .init(color: .black.opacity(0.07), location: 1)]),
            startPoint: CGPoint(x: 0, y: -thickness / 2), endPoint: CGPoint(x: 0, y: thickness / 2)))
        let curl = Color(.sRGB, red: 60 / 255, green: 40 / 255, blue: 20 / 255)
        face.fill(Path(CGRect(x: length * 0.35, y: -thickness / 2, width: length * 0.15, height: thickness)),
                  with: .linearGradient(Gradient(colors: [curl.opacity(0), curl.opacity(0.14 * lift)]),
                                        startPoint: CGPoint(x: length * 0.35, y: 0),
                                        endPoint: CGPoint(x: length / 2, y: 0)))
        if let sheen, sheen > 0, sheen < 1 {
            let x = Ease.lerp(-length / 2 - length * 0.3, length / 2, sheen)
            let shine = Color(.sRGB, red: 1, green: 250 / 255, blue: 236 / 255)
            face.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [shine.opacity(0), shine.opacity(0.35), shine.opacity(0)]),
                startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + length * 0.3, y: 0)))
        }
        ctx.stroke(shape, with: .color(Color(.sRGB, red: 1, green: 250 / 255, blue: 240 / 255, opacity: 0.65)),
                   lineWidth: 0.9)
        var hairs = Path()
        for hair in Self.edge.hairs where hair.u >= u0 {
            let x = -length / 2 + hair.u * length, y = hair.bottom ? thickness / 2 : -thickness / 2
            hairs.move(to: CGPoint(x: x, y: y))
            hairs.addLine(to: CGPoint(x: x + sin(hair.angle) * hair.length * 2,
                                      y: y + (hair.bottom ? 1 : -1) * hair.length * 1.4))
        }
        ctx.stroke(hairs, with: .color(Color(.sRGB, red: 250 / 255, green: 244 / 255, blue: 232 / 255, opacity: 0.75)),
                   style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
    }

    /// The strip at `center`, turned `angle`, at `scale` screen points per
    /// page point.
    func strip(in context: GraphicsContext, at center: CGPoint, angle: CGFloat, scale: CGFloat,
               lift: CGFloat = 1, opacity: CGFloat = 1, sheen: CGFloat? = nil) {
        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: .radians(angle))
        ctx.scaleBy(x: scale, y: scale)
        ribbon(in: ctx, lift: lift, opacity: opacity, sheen: sheen)
    }

    // MARK: Knot

    static func pentagon(_ radius: CGFloat, _ rotation: CGFloat) -> Path {
        var path = Path()
        for k in 0..<5 {
            let angle = (-90 + CGFloat(k) * 72) * .pi / 180 + rotation
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// The knot: plain paper with one washed band per wrap, a dome light,
    /// at most two seams.
    func knotFace(in context: GraphicsContext, radius R: CGFloat, rotation: CGFloat, wraps: CGFloat, shadow: CGFloat) {
        var ctx = context
        let outline = Self.pentagon(R, rotation)
        var lifted = ctx
        lifted.addFilter(.shadow(color: Color(.sRGB, red: 40 / 255, green: 28 / 255, blue: 16 / 255,
                                              opacity: 0.24 * shadow),
                                 radius: R * 0.15 * shadow, x: R * 0.06 * shadow, y: R * 0.14 * shadow))
        lifted.fill(outline, with: .color(PaperArt.paper))
        var face = ctx
        face.clip(to: outline)
        let paint = paper.paint
        for wrap in 0..<min(Self.wraps, Int(ceil(wraps - 1e-6))) {
            var band = face
            band.opacity *= Ease.clamp(wraps - CGFloat(wrap))
            var ring = Self.pentagon(R * (1 - 0.12 * CGFloat(wrap)), rotation)
            ring.addPath(Self.pentagon(R * (1 - 0.12 * CGFloat(wrap + 1)), rotation))
            band.clip(to: ring, style: FillStyle(eoFill: true))
            band.rotate(by: .radians(rotation))
            // This wrap's quarter of the washed strip, stretched over the knot.
            let quarter = paint.textureSize.width / CGFloat(Self.wraps)
            let scaleX = 2 * R / quarter
            band.draw(paint.texture, in: CGRect(x: -R - CGFloat(wrap) * quarter * scaleX, y: -R,
                                                width: paint.textureSize.width * scaleX, height: 2 * R))
        }
        face.fill(Path(CGRect(x: -R * 1.1, y: -R * 1.1, width: R * 2.2, height: R * 2.2)),
                  with: .radialGradient(Gradient(stops: [
                      .init(color: PaperArt.highlight.opacity(0.22), location: 0),
                      .init(color: PaperArt.highlight.opacity(0), location: 0.6),
                      .init(color: PaperArt.brown.opacity(0.12), location: 1)
                  ]), center: CGPoint(x: -R * 0.15, y: -R * 0.18), startRadius: R * 0.05, endRadius: R * 1.05))
        PaperArt.grain(in: face, rect: CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R), opacity: 0.07)
        for seam in 0..<min(2, Int(wraps)) {
            ctx.stroke(Self.pentagon(R * (1 - 0.12 * CGFloat(seam + 1)), rotation),
                       with: .color(Color(.sRGB, red: 90 / 255, green: 64 / 255, blue: 40 / 255, opacity: 0.3)),
                       lineWidth: 0.5)
        }
        ctx.stroke(outline, with: .color(PaperArt.rim.opacity(0.6)), lineWidth: 0.8)
    }

    // MARK: Wind

    // swiftlint:disable function_body_length
    /// The strip winding into the knot, `f` 0 (laid flat, centered at
    /// `mid`) to 1 (all wound, the knot at `mid`): the knot tumbles 72
    /// degrees a wrap along the strip while the rest reels in.
    func wind(in context: GraphicsContext, mid: CGPoint, f: CGFloat) {
        let scale = Self.stage * unit
        let hs = stageThickness, R = knotRadius, wraps = CGFloat(Self.wraps)
        let g = f * wraps, k = min(wraps - 1, floor(g)), phase = f >= 1 ? 1 : g - k
        let stepT = (k + Ease.inOut(phase)) / wraps
        let left = mid.x - length * scale / 2
        let rotation = 72 * .pi / 180 * wraps * stepT
        let knotX = Ease.lerp(left, mid.x, stepT)
        let loopT = Ease.clamp(f / 0.15), loopIn = Ease.clamp(f / 0.04)
        let drop = (0.809 * R - hs / 2) * Ease.sine(loopT)

        // What is left of the strip, leaving the knot's bottom edge.
        let contact = Ease.lerp(left, mid.x, f)
        var rest = context
        rest.translateBy(x: contact - (-length / 2 + f * length) * scale, y: mid.y + drop)
        rest.scaleBy(x: scale, y: scale)
        ribbon(in: rest, from: f)
        guard loopIn > 0 else { return }

        var ctx = context
        ctx.translateBy(x: knotX, y: mid.y)
        if loopT < 1 {
            // A loose loop flattening into the knot.
            var loop = ctx
            loop.opacity *= loopIn * (1 - loopT)
            var ring = Path(ellipseIn: CGRect(x: -R * 0.9, y: -R * 0.9, width: R * 1.8, height: R * 1.8))
            let inner = R * 0.9 - hs * 0.55
            ring.addPath(Path(ellipseIn: CGRect(x: -inner, y: -inner, width: 2 * inner, height: 2 * inner)))
            loop.clip(to: ring, style: FillStyle(eoFill: true))
            loop.draw(paper.strip, in: CGRect(x: -R, y: -R, width: 2 * R / 0.3, height: 2 * R))
        }
        ctx.opacity *= loopIn * loopT
        // Thickness: a layer a wrap.
        let layers = 1 + Int(f * 6)
        for layer in stride(from: layers, through: 1, by: -1) {
            var back = ctx
            back.translateBy(x: 0.6 * CGFloat(layer), y: 1.2 * CGFloat(layer))
            let shade = CGFloat(layer) * 4 / 255
            back.fill(Self.pentagon(R * 0.99, rotation),
                      with: .color(Color(.sRGB, red: 200 / 255 - shade, green: 186 / 255 - shade,
                                         blue: 160 / 255 - shade)))
        }
        knotFace(in: ctx, radius: R, rotation: rotation, wraps: f >= 1 ? wraps : k + phase, shadow: 0.6 + 0.4 * f)
        if f > 0, f < 1, phase < 0.5 {
            // The strip passing over the knot on every other half step.
            let over = sin(phase * 2 * .pi)
            var pass = ctx
            pass.clip(to: Self.pentagon(R, rotation))
            pass.rotate(by: .radians(rotation + 72 * .pi / 180 * Ease.inOut(phase)))
            pass.opacity *= over
            let top = 0.809 * R - hs * 0.55
            var lifted = pass
            lifted.addFilter(.shadow(color: PaperArt.brown.opacity(0.25), radius: 1.5, x: 0, y: 2))
            lifted.fill(Path(CGRect(x: -R * 1.2, y: top, width: R * 2.4, height: hs * 0.55)),
                        with: .color(Color(hex: 0xEEE5D5)))
            pass.fill(Path(CGRect(x: -R * 1.2, y: top, width: R * 2.4, height: 1)),
                      with: .color(PaperArt.cream.opacity(0.8)))
            pass.fill(Path(CGRect(x: -R * 1.2, y: top + hs * 0.55 - 1, width: R * 2.4, height: 1)),
                      with: .color(Color(.sRGB, red: 80 / 255, green: 58 / 255, blue: 36 / 255, opacity: 0.1)))
        }
    }

    // swiftlint:enable function_body_length

    // MARK: Page

    /// The page's size on screen at `scale` of full size.
    func pageSize(_ scale: CGFloat) -> CGSize {
        CGSize(width: paper.pageSize.width * unit * scale, height: paper.pageSize.height * unit * scale)
    }

    // swiftlint:disable:next large_tuple
    typealias Band = (center: CGPoint, angle: CGFloat, scale: CGFloat)

    /// Where the cut lies on a page centered at `center` at `scale`.
    func band(pageCenter center: CGPoint, scale: CGFloat) -> Band {
        let s = scale * unit
        return (CGPoint(x: center.x + (paper.cutCenter.x - paper.pageSize.width / 2) * s,
                        y: center.y + (paper.cutCenter.y - paper.pageSize.height / 2) * s),
                paper.cutAngle, s)
    }

    struct PageMarks {
        /// The empty slot where the strip was.
        var slot: CGFloat = 0
        /// The blade's score lines along the cut, 0...1.2.
        var score: CGFloat = 0
        /// Only this half-width around the band shows (unrolling), page points.
        var mask: CGFloat?
    }

    // swiftlint:disable:next function_body_length
    func page(in context: GraphicsContext, center: CGPoint, scale: CGFloat, corner: CGFloat, opacity: CGFloat = 1,
              shadow: CGFloat = 0, marks: PageMarks = PageMarks()) {
        guard opacity > 0 else { return }
        var ctx = context
        ctx.opacity *= opacity
        let s = scale * unit
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -paper.pageSize.width / 2, y: -paper.pageSize.height / 2)
        let card = Path(roundedRect: CGRect(origin: .zero, size: paper.pageSize), cornerRadius: max(0.1, corner / s))
        if shadow > 0, marks.mask == nil {
            // A baked shadow: a live blur of the whole page every frame
            // costs the shrink its frames.
            var lifted = ctx
            lifted.opacity *= shadow
            let margin = StarPaper.shadowMargin
            lifted.draw(paper.pageShadow,
                        in: CGRect(origin: .zero, size: paper.pageSize).insetBy(dx: -margin, dy: -margin))
        }
        var sheet = ctx
        sheet.clip(to: card)
        if let mask = marks.mask {
            var shown = Path(CGRect(x: -paper.pageSize.height * 2, y: -mask,
                                    width: paper.pageSize.height * 4, height: mask * 2))
            shown = shown.applying(CGAffineTransform(rotationAngle: paper.cutAngle)
                .concatenating(CGAffineTransform(translationX: paper.cutCenter.x, y: paper.cutCenter.y)))
            sheet.clip(to: shown)
        }
        sheet.fill(card, with: .color(Color(hex: 0xF4EEE3)))
        sheet.draw(paper.page, in: CGRect(origin: .zero, size: paper.pageSize))
        if let mask = marks.mask, mask > 12 {
            // A feathered edge, so words are never sliced mid-glyph.
            var feather = sheet
            feather.translateBy(x: paper.cutCenter.x, y: paper.cutCenter.y)
            feather.rotate(by: .radians(paper.cutAngle))
            let paperColor = Color(hex: 0xF4EEE3)
            for side: CGFloat in [-1, 1] {
                let edge = side * mask, inside = side * (mask - 10)
                feather.fill(Path(CGRect(x: -paper.pageSize.height * 2, y: min(edge, inside),
                                         width: paper.pageSize.height * 4, height: 10)),
                             with: .linearGradient(Gradient(colors: [paperColor, paperColor.opacity(0)]),
                                                   startPoint: CGPoint(x: 0, y: edge),
                                                   endPoint: CGPoint(x: 0, y: inside)))
            }
        }
        if marks.slot > 0 || marks.score > 0 {
            var cut = sheet
            cut.translateBy(x: paper.cutCenter.x, y: paper.cutCenter.y)
            cut.rotate(by: .radians(paper.cutAngle))
            let shape = ribbonPath(from: 0)
            if marks.slot > 0 {
                var slot = cut
                slot.opacity *= marks.slot
                slot.fill(shape, with: .color(Color(hex: 0xEDE5D7)))
                slot.fill(shape,
                          with: .color(Color(.sRGB, red: 120 / 255, green: 96 / 255, blue: 64 / 255, opacity: 0.1)))
                slot.stroke(line(at: -thickness / 2 + 1, to: length),
                            with: .color(Color(.sRGB, red: 80 / 255, green: 58 / 255, blue: 36 / 255, opacity: 0.28)),
                            lineWidth: 1 / s)
            }
            if marks.score > 0, marks.score < 1.2 {
                var score = cut
                score.opacity *= marks.score > 1 ? 1 - (marks.score - 1) / 0.2 : 1
                let reach = length * Ease.clamp(marks.score)
                for y in [-thickness / 2, thickness / 2] {
                    score.stroke(line(at: y - 0.5 / s, to: reach), with: .color(.white), lineWidth: 1.5 / s)
                    score.stroke(line(at: y + 0.6 / s, to: reach),
                                 with: .color(Color(.sRGB, red: 60 / 255, green: 40 / 255, blue: 20 / 255,
                                                    opacity: 0.5)),
                                 lineWidth: 0.6 / s)
                }
            }
        }
    }

    /// A faint page with its empty slot, for the opening strip to dock on.
    func pageGhost(in context: GraphicsContext, center: CGPoint, scale: CGFloat, corner: CGFloat, opacity: CGFloat) {
        guard opacity > 0 else { return }
        var ctx = context
        ctx.opacity *= opacity
        let s = scale * unit
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -paper.pageSize.width / 2, y: -paper.pageSize.height / 2)
        let card = Path(roundedRect: CGRect(origin: .zero, size: paper.pageSize), cornerRadius: max(0.1, corner / s))
        ctx.fill(card, with: .color(Color(hex: 0xF4EEE3)))
        ctx.stroke(card, with: .color(Color(.sRGB, red: 120 / 255, green: 96 / 255, blue: 64 / 255, opacity: 0.25)),
                   lineWidth: 1 / s)
        ctx.translateBy(x: paper.cutCenter.x, y: paper.cutCenter.y)
        ctx.rotate(by: .radians(paper.cutAngle))
        ctx.fill(ribbonPath(from: 0), with: .color(Color(hex: 0xE6DCCB)))
        ctx.stroke(line(at: -thickness / 2 + 1, to: length),
                   with: .color(Color(.sRGB, red: 80 / 255, green: 58 / 255, blue: 36 / 255, opacity: 0.3)),
                   lineWidth: 1 / s)
    }

    private func line(at y: CGFloat, to reach: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -length / 2, y: y))
        path.addLine(to: CGPoint(x: -length / 2 + reach, y: y))
        return path
    }
}
// swiftlint:enable identifier_name
