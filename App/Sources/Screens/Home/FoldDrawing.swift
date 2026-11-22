import MiraNoteKit
import SwiftUI

// A port of design X's canvas maths (debug/star-anim/X/proto.html): t
// (ms), p/q/u (progress), R (radius), S (roll length), k (arm or scale)
// read as the formulas they are; longer names would hide them. The
// page's geometry is FoldGeometry.swift, its marks FoldPage.swift.
// swiftlint:disable identifier_name

// MARK: - Strip, knot and star

/// The strip, the knot it winds into and the star it puffs into, ported
/// from the prototype's drawStrip, drawWind and drawFolded.
struct FoldDrawing {
    let paper: StarPaper

    static let length = StarPaper.width
    static let thickness = StarPaper.tile
    static let rolls = 5
    /// A roll's length along the strip.
    static let roll = length / CGFloat(rolls + 1)
    static let cos36 = cos(36 * CGFloat.pi / 180)
    /// The knot's radius, drawn 1.35x its fold pitch.
    static let knot = roll / (2 * sin(36 * CGFloat.pi / 180)) * 1.35
    /// The hero zoom and star radius (about 100 pt).
    static let heroZoom: CGFloat = 1.45
    static let hero = knot * heroZoom
    /// The width the camera keeps strip and knot inside.
    static let fitWidth: CGFloat = 340
    /// The strip's middle shows on the star's faces.
    static let faceU = length / 2
    static let rollAngle = 72 * CGFloat.pi / 180
    static let wound = CGFloat(rolls) * rollAngle
    static let twist = 14 * CGFloat.pi / 180
    static let spin = 200 * CGFloat.pi / 180

    /// Where the knot is after `n` rolls (world x, the band's frame).
    static func knotX(_ n: CGFloat) -> CGFloat { -length / 2 + roll / 2 + n * roll }

    /// One fold a unit of `g`, each eased, so the eye sees tumbles.
    static func step(_ g: CGFloat) -> CGFloat {
        if g >= CGFloat(rolls) { return CGFloat(rolls) }
        if g <= 0 { return 0 }
        let k = floor(g), ph = g - k
        return k + Ease.lerp(ph, Ease.inOut3(ph), 0.65)
    }

    /// The camera that frames what is left of the strip plus the knot.
    static func fitZoom(_ n: CGFloat) -> CGFloat {
        min(heroZoom, fitWidth / (length / 2 - knotX(n) + knot * 1.15))
    }

    static func fitX(_ n: CGFloat) -> CGFloat { (knotX(n) - knot * 1.15 + length / 2) / 2 }

    // MARK: Strip

    // swiftlint:disable function_body_length function_parameter_count
    /// The strip in its own frame, its middle at the origin: from `u0`
    /// (0...1 along it, where the knot has reached) to its end, with a
    /// paper ripple, its free end curling up into the knot, a lift shadow
    /// and its folded-up layers showing at its foot.
    func strip(in context: GraphicsContext, from u0: CGFloat, lift: CGFloat, ripple: CGFloat, phase: CGFloat,
               curl: CGFloat) {
        let L = Self.length, SW = Self.thickness
        let x0 = -L / 2 + Ease.clamp(u0) * L, x1 = L / 2
        guard x1 - x0 >= 0.5 else { return }
        func z(_ u: CGFloat) -> CGFloat {
            ripple * sin(u / 46 + phase) * (0.65 + 0.35 * sin(u / 19 - phase * 1.3))
        }
        let n = max(1, Int(ceil((x1 - x0) / 8))), dx = (x1 - x0) / CGFloat(n)
        let ys: [CGFloat] = (0...n).map { i in
            let u = x0 + CGFloat(i) * dx, cq = max(0, 1 - (u - x0) / 150)
            return z(u) * 0.3 - curl * pow(cq, 1.3)
        }
        var outline = Path()
        for i in 0...n {
            let point = CGPoint(x: x0 + CGFloat(i) * dx, y: -SW / 2 + ys[i])
            if i == 0 { outline.move(to: point) } else { outline.addLine(to: point) }
        }
        for i in stride(from: n, through: 0, by: -1) {
            outline.addLine(to: CGPoint(x: x0 + CGFloat(i) * dx, y: SW / 2 + ys[i]))
        }
        outline.closeSubpath()

        var ctx = context
        if lift > 0.001 {
            var shadow = ctx
            shadow.addFilter(.shadow(color: Color(.sRGB, red: 80 / 255, green: 42 / 255, blue: 34 / 255,
                                                  opacity: 0.28 * min(1, lift)),
                                     radius: (3 + 13 * lift) / 2, x: 2.5 * lift, y: 8 * lift))
            shadow.fill(outline, with: .color(Color(hex: 0xD9A08E)))
        }
        // The folded-up layers at its foot.
        var layers = ctx
        layers.translateBy(x: 0, y: 1.8)
        layers.fill(outline, with: .color(Color(.sRGB, red: 120 / 255, green: 60 / 255, blue: 64 / 255, opacity: 0.5)))

        let image = ctx.resolve(paper.strip)
        for i in 0..<n {
            let u = x0 + CGFloat(i) * dx, slope = (ys[i + 1] - ys[i]) / dx
            var slice = ctx
            slice.concatenate(CGAffineTransform(a: 1, b: slope, c: 0, d: 1, tx: u, ty: ys[i]))
            let width = min(dx + 0.7, L / 2 - u)
            slice.clip(to: Path(CGRect(x: 0, y: -SW / 2, width: max(0.1, width), height: SW)))
            slice.draw(image, in: CGRect(x: -(u + L / 2), y: -SW / 2, width: L, height: SW))
            let d = slope * 3.3
            if abs(d) > 0.002 {
                let shade = d > 0 ? Color(.sRGB, red: 1, green: 248 / 255, blue: 240 / 255, opacity: min(0.3, d * 2.2))
                    : Color(.sRGB, red: 70 / 255, green: 30 / 255, blue: 30 / 255, opacity: min(0.26, -d * 1.8))
                slice.fill(Path(CGRect(x: 0, y: -SW / 2, width: dx, height: SW)), with: .color(shade))
            }
        }
        var face = ctx
        face.clip(to: outline)
        let rect = CGRect(x: x0, y: -SW / 2 - 4, width: x1 - x0, height: SW + 8)
        face.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [.init(color: Color(.sRGB, red: 1, green: 250 / 255, blue: 244 / 255, opacity: 0.14),
                                   location: 0),
                             .init(color: Color(.sRGB, red: 1, green: 250 / 255, blue: 244 / 255, opacity: 0),
                                   location: 0.45),
                             .init(color: Color(.sRGB, red: 60 / 255, green: 25 / 255, blue: 30 / 255, opacity: 0.09),
                                   location: 1)]),
            startPoint: CGPoint(x: 0, y: -SW / 2), endPoint: CGPoint(x: 0, y: SW / 2)))
        PaperArt.grain(in: face, rect: rect, opacity: 0.06)
        for (edge, color) in [(-SW / 2 + 0.4, Color(.sRGB, red: 1, green: 250 / 255, blue: 245 / 255, opacity: 0.7)),
                              (SW / 2 - 0.4, Color(.sRGB, red: 1, green: 240 / 255, blue: 235 / 255, opacity: 0.3))] {
            var line = Path()
            for i in 0...n {
                let point = CGPoint(x: x0 + CGFloat(i) * dx, y: edge + ys[i])
                if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            ctx.stroke(line, with: .color(color), lineWidth: 0.8)
        }
    }
    // swiftlint:enable function_body_length

    /// The wrapped layers a knot shows after `n` rolls.
    static func bands(_ n: CGFloat) -> [FoldedStar.Band] {
        let done = min(rolls, Int(floor(n + 1e-6)))
        let ph = done >= rolls ? 0 : n - CGFloat(done)
        return (0...min(rolls, done + 1)).compactMap { j in
            let reveal = j <= done ? 1 : ph
            guard reveal > 0 else { return nil }
            return FoldedStar.Band(angle: -CGFloat(j) * rollAngle, reveal: reveal, u: (CGFloat(j) + 0.5) * roll)
        }
    }

    /// The strip winding into the knot after `n` rolls; `tie` is the
    /// first loop (0...1). In the band's frame, its middle at the origin.
    func wind(in context: GraphicsContext, n: CGFloat, tie: CGFloat, lift: CGFloat, ripple: CGFloat,
              phase: CGFloat) {
        let rolls = CGFloat(Self.rolls)
        let u0 = (tie * 0.5 + n) * Self.roll / Self.length
        strip(in: context, from: tie > 0 ? u0 : 0, lift: lift, ripple: ripple, phase: phase,
              curl: tie > 0 && n < rolls - 0.02 ? Self.thickness * 0.7 * min(1, tie * 1.5) : 0)
        guard tie > 0 else { return }
        // swiftlint:enable function_parameter_count
        let sc = Ease.lerp(0.3, 1, Ease.outBack(tie, 1.2))
        let rotation = n * Self.rollAngle + Ease.lerp(-110 * .pi / 180, 0, Ease.out3(tie))
        var bands = Self.bands(n)
        if n < 1e-6, !bands.isEmpty {
            bands[0] = FoldedStar.Band(angle: bands[0].angle, reveal: tie, u: bands[0].u)
        }
        FoldedStar.draw(in: context, paper: paper, at: CGPoint(x: Self.knotX(n), y: 0), radius: Self.knot * sc,
                        rotation: rotation,
                        look: .init(puff: 0, faceU: Ease.lerp((n + 1) * Self.roll, Self.faceU, n / rolls),
                                    bands: bands, k: sc, layers: n, shadow: 0.5 + 0.5 * min(1, lift),
                                    opacity: Ease.clamp(tie * 2.5)))
    }
}

// MARK: - Folded star

/// The knot (puff 0, a flat pentagon) to the matte lucky star (puff 1),
/// ten facets under one fixed light, wrapped strip layers on the knot,
/// paper thickness, grain and a soft rim (the prototype's drawFolded).
enum FoldedStar {
    struct Band {
        let angle: CGFloat
        let reveal: CGFloat
        /// Where on the strip this layer comes from.
        let u: CGFloat
    }

    struct Look {
        var puff: CGFloat = 1
        var faceU = FoldDrawing.faceU
        var bands: [Band] = []
        /// Screen points per world point, so the bands show the strip true.
        var k: CGFloat = 1
        var layers: CGFloat = 0
        var shadow: CGFloat = 0
        var opacity: CGFloat = 1
    }

    // swiftlint:disable:next large_tuple
    private static let light: (x: CGFloat, y: CGFloat, z: CGFloat) = {
        let x: CGFloat = -0.5, y: CGFloat = -0.62, z: CGFloat = 0.6
        let m = (x * x + y * y + z * z).squareRoot()
        return (x / m, y / m, z / m)
    }()

    static func points(_ R: CGFloat, inner: CGFloat, rotation: CGFloat) -> [CGPoint] {
        (0..<5).flatMap { k -> [CGPoint] in
            let a = -.pi / 2 + CGFloat(k) * 72 * .pi / 180 + rotation, b = a + 36 * .pi / 180
            return [CGPoint(x: cos(a) * R, y: sin(a) * R), CGPoint(x: cos(b) * R * inner, y: sin(b) * R * inner)]
        }
    }

    /// The polygon with its tips rounded by `tip` and valleys by `valley`.
    static func rounded(_ p: [CGPoint], tip: CGFloat, valley: CGFloat) -> Path {
        var path = Path()
        let n = p.count
        for i in 0..<n {
            let P = p[i], A = p[(i + n - 1) % n], B = p[(i + 1) % n], r = i % 2 == 1 ? valley : tip
            let la = max(hypot(A.x - P.x, A.y - P.y), 1e-6), lb = max(hypot(B.x - P.x, B.y - P.y), 1e-6)
            let ta = min(0.45, r / la), tb = min(0.45, r / lb)
            let a0 = CGPoint(x: P.x + (A.x - P.x) * ta, y: P.y + (A.y - P.y) * ta)
            let b0 = CGPoint(x: P.x + (B.x - P.x) * tb, y: P.y + (B.y - P.y) * tb)
            if i == 0 { path.move(to: a0) } else { path.addLine(to: a0) }
            path.addQuadCurve(to: b0, control: P)
        }
        path.closeSubpath()
        return path
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity function_parameter_count
    static func draw(in context: GraphicsContext, paper: StarPaper, at center: CGPoint, radius R: CGFloat,
                     rotation: CGFloat, look: Look) {
        guard R >= 0.4, look.opacity > 0.002 else { return }
        let pf = look.puff, pfc = Ease.clamp(pf)
        let inner = Ease.lerp(cos36Value, 0.58, pf), h = R * Ease.lerp(0.16, 0.5, pfc)
        let p = points(R, inner: inner, rotation: rotation)
        let outline = rounded(p, tip: R * Ease.lerp(0.09, 0.2, pfc), valley: R * 0.13 * pfc)
        let k = look.k
        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.opacity *= look.opacity
        if look.shadow > 0 {
            var shadow = ctx
            shadow.addFilter(.shadow(color: Color(.sRGB, red: 72 / 255, green: 38 / 255, blue: 30 / 255,
                                                  opacity: 0.3 * min(1.2, look.shadow)),
                                     radius: R * 0.19, x: R * 0.08, y: R * 0.2))
            shadow.fill(outline, with: .color(Color(hex: 0xE2A493)))
        }
        // Paper thickness: the stacked layers peek out lower right.
        var thick = ctx
        thick.translateBy(x: R * (0.02 + 0.004 * look.layers), y: R * (0.04 + 0.007 * look.layers))
        thick.fill(outline, with: .color(Color(.sRGB, red: 128 / 255, green: 66 / 255, blue: 66 / 255, opacity: 0.42)))

        var face = ctx
        face.clip(to: outline)
        let L = FoldDrawing.length, SW = FoldDrawing.thickness
        do {
            var turned = face
            turned.rotate(by: .radians(rotation))
            let sw = min(L, 4.6 * R / k), sx = Ease.clamp(look.faceU - sw / 2, 0, L - sw)
            let sxScale = 2.2 * R / sw
            turned.draw(paper.face, in: CGRect(x: -1.1 * R - sx * sxScale, y: -1.1 * R, width: L * sxScale,
                                               height: 2.2 * R))
        }
        let bandsShown = Ease.clamp(1 - pfc * 1.7)
        if bandsShown > 0, !look.bands.isEmpty {
            let ap = R * cos36Value, bh = SW * 0.5 * k, bsw = 2 * R / k
            let strip = face.resolve(paper.strip)
            for band in look.bands where band.reveal > 0 {
                var layer = face
                layer.rotate(by: .radians(rotation + band.angle))
                layer.opacity *= bandsShown
                let rx = R - 2 * R * band.reveal
                layer.clip(to: Path(CGRect(x: rx, y: ap - bh - 6, width: R - rx + 1, height: bh + 8)))
                layer.fill(Path(CGRect(x: -R, y: ap - bh - 5, width: 2 * R, height: 5)), with: .linearGradient(
                    Gradient(colors: [Color(.sRGB, red: 60 / 255, green: 25 / 255, blue: 28 / 255, opacity: 0),
                                      Color(.sRGB, red: 60 / 255, green: 25 / 255, blue: 28 / 255, opacity: 0.2)]),
                    startPoint: CGPoint(x: 0, y: ap - bh - 5), endPoint: CGPoint(x: 0, y: ap - bh)))
                var wrap = layer
                wrap.clip(to: Path(CGRect(x: -R, y: ap - bh, width: 2 * R, height: bh + 1)))
                let bsx = Ease.clamp(band.u - bsw / 2, 0, L - bsw), sx = 2 * R / bsw, sy = (bh + 1) / (SW * 0.5)
                wrap.draw(strip, in: CGRect(x: -R - bsx * sx, y: ap - bh, width: L * sx, height: SW * sy))
                layer.fill(Path(CGRect(x: -R, y: ap - bh, width: 2 * R, height: bh)), with: .linearGradient(
                    Gradient(colors: [Color(.sRGB, red: 1, green: 244 / 255, blue: 234 / 255, opacity: 0.12),
                                      Color(.sRGB, red: 80 / 255, green: 34 / 255, blue: 40 / 255, opacity: 0.16)]),
                    startPoint: CGPoint(x: 0, y: ap - bh), endPoint: CGPoint(x: 0, y: ap)))
                layer.fill(Path(CGRect(x: -R, y: ap - bh, width: 2 * R, height: max(0.6, 0.025 * R))),
                           with: .color(Color(.sRGB, red: 1, green: 246 / 255, blue: 238 / 255, opacity: 0.55)))
                let seam = max(0.6, 0.02 * R)
                layer.fill(Path(CGRect(x: -R, y: ap - bh - seam, width: 2 * R, height: seam)),
                           with: .color(Color(.sRGB, red: 90 / 255, green: 40 / 255, blue: 46 / 255, opacity: 0.3)))
            }
        }
        // Ten facets lit by one fixed light (matte: light and shade capped).
        let fm = Ease.lerp(0.4, 1, pfc)
        for f in 0..<5 {
            let T = p[2 * f]
            for (A, B) in [(p[(2 * f + 9) % 10], T), (T, p[2 * f + 1])] {
                var nx = h * (B.y - A.y), ny = h * (A.x - B.x), nz = A.x * B.y - A.y * B.x
                if nz < 0 { nx = -nx; ny = -ny; nz = -nz }
                let m = max((nx * nx + ny * ny + nz * nz).squareRoot(), 1e-6)
                let d = (nx * light.x + ny * light.y + nz * light.z) / m - light.z
                var tri = Path()
                tri.move(to: .zero)
                tri.addLine(to: CGPoint(x: A.x * 1.02, y: A.y * 1.02))
                tri.addLine(to: CGPoint(x: B.x * 1.02, y: B.y * 1.02))
                tri.closeSubpath()
                face.fill(tri, with: .color(d > 0
                    ? Color(.sRGB, red: 1, green: 238 / 255, blue: 226 / 255, opacity: fm * min(0.2, d * 0.8))
                    : Color(.sRGB, red: 70 / 255, green: 30 / 255, blue: 40 / 255, opacity: fm * min(0.3, -d * 0.9))))
            }
        }
        if pfc > 0 {
            let valley = Color(.sRGB, red: 70 / 255, green: 28 / 255, blue: 30 / 255)
            for v in 0..<5 {
                let I = p[2 * v + 1]
                face.fill(Path(CGRect(x: I.x - R * 0.35, y: I.y - R * 0.35, width: R * 0.7, height: R * 0.7)),
                          with: .radialGradient(Gradient(colors: [valley.opacity(0.18 * pfc), valley.opacity(0)]),
                                                center: I, startRadius: 0, endRadius: R * 0.34))
            }
            let width = max(0.25, R * 0.022)
            for r in 0..<5 {
                let tip = p[2 * r], dip = p[2 * r + 1]
                var ridge = Path()
                ridge.move(to: .zero)
                ridge.addLine(to: CGPoint(x: tip.x * 0.86, y: tip.y * 0.86))
                face.stroke(ridge, with: .color(Color(.sRGB, red: 1, green: 240 / 255, blue: 230 / 255,
                                                      opacity: 0.16 * pfc)),
                            style: StrokeStyle(lineWidth: width, lineCap: .round))
                var groove = Path()
                groove.move(to: .zero)
                groove.addLine(to: CGPoint(x: dip.x * 0.9, y: dip.y * 0.9))
                face.stroke(groove, with: .color(Color(.sRGB, red: 90 / 255, green: 40 / 255, blue: 38 / 255,
                                                       opacity: 0.13 * pfc)),
                            style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        face.fill(Path(CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R)), with: .radialGradient(
            Gradient(colors: [Color(.sRGB, red: 1, green: 244 / 255, blue: 234 / 255, opacity: 0.05 * (1 - pfc)),
                              Color(.sRGB, red: 1, green: 253 / 255, blue: 247 / 255, opacity: 0)]),
            center: CGPoint(x: -R * 0.32, y: -R * 0.38), startRadius: 0, endRadius: R * 0.95))
        if R > 6 { PaperArt.grain(in: face, rect: CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R), opacity: 0.12) }
        // The rim: soft lit top-left edge, darker lower right.
        ctx.stroke(outline, with: .linearGradient(
            Gradient(stops: [.init(color: Color(.sRGB, red: 1, green: 242 / 255, blue: 232 / 255, opacity: 0.32),
                                   location: 0),
                             .init(color: Color(.sRGB, red: 1, green: 242 / 255, blue: 232 / 255, opacity: 0.06),
                                   location: 0.55),
                             .init(color: Color(.sRGB, red: 90 / 255, green: 44 / 255, blue: 40 / 255, opacity: 0.24),
                                   location: 1)]),
            startPoint: CGPoint(x: -R, y: -R), endPoint: CGPoint(x: R, y: R)),
                   style: StrokeStyle(lineWidth: max(0.3, R * 0.026), lineJoin: .round))
    }

    private static let cos36Value = FoldDrawing.cos36
}
// swiftlint:enable identifier_name
