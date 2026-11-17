import MiraNoteKit
import SwiftUI
import UIKit

/// A star's dress for drawing: its washed strip, five arm tints and its
/// average (`StarStrip.look`).
struct StarPaint {
    let texture: Image
    /// The texture's size in pixels: long side along the strip.
    let textureSize: CGSize
    let tints: [Color]
    let average: Color

    init(_ look: StarLook) {
        texture = Image(uiImage: PaperArt.image(look.texture))
        textureSize = CGSize(width: look.texture.width, height: look.texture.height)
        tints = look.tints.map(PaperArt.color)
        average = PaperArt.color(look.average)
    }

    /// A plain paper star: a page whose face is not baked yet.
    static let paper = StarPaint(StarStrip.look(StarPixels(width: 40, height: 8, fill: StarColor(236, 228, 212))))
}

/// What a star wears under its light: its page's paint, drawn live, or
/// that paint baked once into an upright image (`PaperStar.dressing`).
enum StarDress {
    case paint(StarPaint)
    case baked(Image)
}

/// The matte puffy paper star of the fold demo (v4, `drawStar`): rounded
/// points, bowed sides, the page's washed colors with a flat tint per
/// arm, each arm lit on one side and shaded on the other, darker valleys,
/// a dome highlight from the top left, a rim light, paper grain and a
/// soft shadow. Every star in the app is this one drawing: the jar's, the
/// toss's, the fold's and the open's.
enum PaperStar {
    /// The ten points: tips at `radius`, valleys at `radius * inner[k]`,
    /// the first tip straight up, turned by `rotation` radians.
    static func points(radius: CGFloat, inner: [CGFloat], rotation: CGFloat) -> [CGPoint] {
        (0..<5).flatMap { k -> [CGPoint] in
            let tip = (-90 + CGFloat(k) * 72) * .pi / 180 + rotation
            let valley = (-54 + CGFloat(k) * 72) * .pi / 180 + rotation
            return [
                CGPoint(x: cos(tip) * radius, y: sin(tip) * radius),
                CGPoint(x: cos(valley) * radius * inner[k], y: sin(valley) * radius * inner[k])
            ]
        }
    }

    /// Rounded tips (`round` of each side), sides bowed out by `bow`.
    static func path(_ p: [CGPoint], bow: CGFloat, round: CGFloat) -> Path {
        func near(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * round, y: a.y + (b.y - a.y) * round)
        }
        func bowed(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2 * (1 - bow), y: (a.y + b.y) / 2 * (1 - bow))
        }
        var path = Path()
        for k in 0..<5 {
            let tip = p[k * 2], before = p[(k * 2 + 9) % 10], after = p[k * 2 + 1]
            let a = near(tip, before), b = near(tip, after)
            if k == 0 { path.move(to: a) } else { path.addQuadCurve(to: a, control: bowed(before, a)) }
            path.addQuadCurve(to: b, control: tip)
            path.addQuadCurve(to: after, control: bowed(b, after))
        }
        let first = near(p[0], p[9])
        path.addQuadCurve(to: first, control: bowed(p[9], first))
        path.closeSubpath()
        return path
    }

    struct Style {
        var shadow: CGFloat = 0
        /// The hero's deeper shadow (pinch, throw, open).
        var hero = false
        /// 1 = full puff light; nil = from how deep the valleys are.
        var puff: CGFloat?
        var opacity: CGFloat = 1
    }

    /// The dress under the light, upright in a 2.1 `radius` square
    /// centered at the origin: the washed strip's middle under five flat
    /// arm tints. The star's outline clips it; its light is drawn over it
    /// unturned, so a turned star keeps its light from the top left.
    static func dressing(in context: GraphicsContext, radius R: CGFloat, paint: StarPaint) {
        let scale = R * 2.1 / paint.textureSize.height
        context.draw(paint.texture, in: CGRect(
            x: -paint.textureSize.width / 2 * scale, y: -R * 1.05,
            width: paint.textureSize.width * scale, height: R * 2.1
        ))
        let reach = R * 0.809, band = R * 0.5
        for k in 0..<5 {
            var arm = context
            arm.rotate(by: .degrees(-144 + Double(k) * 72))
            arm.opacity *= 0.92 * 0.8
            arm.fill(Path(CGRect(x: -R * 1.15, y: reach - band, width: R * 2.3, height: band + R * 0.3)),
                     with: .color(paint.tints[k]))
        }
    }

    static func draw(
        in context: GraphicsContext, at center: CGPoint, radius: CGFloat, inner: [CGFloat],
        rotation: CGFloat, paint: StarPaint, style: Style = Style()
    ) {
        draw(in: context, at: center, radius: radius, inner: inner, rotation: rotation, dress: .paint(paint),
             style: style)
    }

    /// Draws the star centered at `center`.
    static func draw(
        in context: GraphicsContext, at center: CGPoint, radius: CGFloat, inner: [CGFloat],
        rotation: CGFloat, dress: StarDress, style: Style = Style()
    ) {
        guard radius >= 0.5, style.opacity > 0 else { return }
        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.opacity *= style.opacity
        let average = inner.reduce(0, +) / CGFloat(inner.count)
        let puff = style.puff ?? min(1, max(0, (0.809 - average) / 0.209))
        let p = points(radius: radius, inner: inner, rotation: rotation)
        let outline = path(p, bow: 0.08 * puff, round: 0.07 + 0.03 * puff)
        let R = radius

        if style.shadow > 0 {
            var shadow = ctx
            let s = style.shadow
            shadow.addFilter(.shadow(
                color: PaperArt.brown.opacity((style.hero ? 0.34 : 0.26) * s),
                radius: (style.hero ? 14 : R * 0.35) * s / 2,
                x: R * 0.08 * s, y: (style.hero ? 6 : R * 0.16) * s
            ))
            shadow.fill(outline, with: .color(Color(hex: 0xE6DCCB)))
        }

        var face = ctx
        face.clip(to: outline)
        var turned = face
        turned.rotate(by: .radians(rotation))
        switch dress {
        case .paint(let paint): dressing(in: turned, radius: R, paint: paint)
        case .baked(let image): turned.draw(image, in: CGRect(x: -R * 1.05, y: -R * 1.05, width: R * 2.1, height: R * 2.1))
        }

        if puff > 0 {
            // Each arm lit on its upper-left side, shaded on the other.
            let light = CGPoint(x: cos(-135 * CGFloat.pi / 180), y: sin(-135 * CGFloat.pi / 180))
            for arm in 0..<5 {
                let tip = p[arm * 2], before = p[(arm * 2 + 9) % 10], after = p[arm * 2 + 1]
                let dx = after.x - before.x, dy = after.y - before.y
                let lit = (dx * light.x + dy * light.y) / max(hypot(dx, dy), 0.001) < 0
                let bright = PaperArt.cream.opacity(0.1 * puff), dark = PaperArt.brown.opacity(0.1 * puff)
                var triangle = Path()
                triangle.move(to: .zero)
                triangle.addLine(to: before)
                triangle.addLine(to: tip)
                triangle.addLine(to: after)
                triangle.closeSubpath()
                face.fill(triangle, with: .linearGradient(
                    Gradient(stops: [.init(color: lit ? bright : dark, location: 0),
                                     .init(color: .clear, location: 0.5),
                                     .init(color: lit ? dark : bright, location: 1)]),
                    startPoint: before, endPoint: after
                ))
            }
            // Darker valleys.
            for valley in 0..<5 {
                let point = p[valley * 2 + 1]
                face.fill(Path(CGRect(x: point.x - R * 0.4, y: point.y - R * 0.4, width: R * 0.8, height: R * 0.8)),
                          with: .radialGradient(Gradient(colors: [PaperArt.brown.opacity(0.14 * puff),
                                                                  PaperArt.brown.opacity(0)]),
                                                center: point, startRadius: 0, endRadius: R * 0.38))
            }
        }
        // The dome: light from the top left, a little dark low right.
        face.fill(Path(CGRect(x: -R * 1.1, y: -R * 1.1, width: R * 2.2, height: R * 2.2)),
                  with: .radialGradient(Gradient(stops: [
                      .init(color: PaperArt.highlight.opacity(0.08 + 0.14 * puff), location: 0),
                      .init(color: PaperArt.highlight.opacity(0), location: 0.55),
                      .init(color: PaperArt.brown.opacity(0.04 + 0.08 * puff), location: 1)
                  ]), center: CGPoint(x: -R * 0.12, y: -R * 0.15), startRadius: R * 0.04, endRadius: R * 1.05))
        if R > 8 { PaperArt.grain(in: face, rect: CGRect(x: -R, y: -R, width: R * 2, height: R * 2), opacity: 0.07) }

        if R > 4 {
            // A rim of light on the upper-left edges, a hairline all round.
            var rim = ctx
            var half = Path()
            half.move(to: CGPoint(x: -R * 2, y: R * 2))
            half.addLine(to: CGPoint(x: R * 2, y: -R * 2))
            half.addLine(to: CGPoint(x: -R * 2, y: -R * 2))
            half.closeSubpath()
            rim.clip(to: half)
            rim.stroke(outline, with: .color(PaperArt.rim.opacity(0.35 + 0.25 * puff)), lineWidth: max(0.6, R * 0.035))
            ctx.stroke(outline, with: .color(Color(.sRGB, red: 90 / 255, green: 64 / 255, blue: 40 / 255, opacity: 0.14)),
                       lineWidth: max(0.4, R * 0.02))
        }
    }

    /// The star at rest: valleys at 0.6.
    static let rest: [CGFloat] = Array(repeating: 0.6, count: 5)
}

/// A star at rest in a frame (jar, toss): `PaperStar` with a light
/// shadow, turned `rotation` radians under a light that stays top left,
/// nudged down so the five tips sit centered in the frame.
struct PaperStarView: View {
    let dress: StarDress
    var rotation: CGFloat = 0

    init(dress: StarDress, rotation: CGFloat = 0) {
        self.dress = dress
        self.rotation = rotation
    }

    init(paint: StarPaint) {
        self.init(dress: .paint(paint))
    }

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) * 0.45
            PaperStar.draw(
                in: context, at: CGPoint(x: size.width / 2, y: size.height / 2 + radius * 0.07),
                radius: radius, inner: PaperStar.rest, rotation: rotation, dress: dress,
                style: .init(shadow: 0.35)
            )
        }
    }
}

/// The paper colors and textures the fold's drawings share.
enum PaperArt {
    static let brown = Color(.sRGB, red: 40 / 255, green: 26 / 255, blue: 12 / 255)
    static let cream = Color(.sRGB, red: 1, green: 252 / 255, blue: 244 / 255)
    static let highlight = Color(.sRGB, red: 1, green: 253 / 255, blue: 246 / 255)
    static let rim = Color(.sRGB, red: 1, green: 251 / 255, blue: 240 / 255)
    /// The knot's and a strip's back: plain paper.
    static let paper = Color(hex: 0xEFE6D6)

    static func color(_ color: StarColor) -> Color {
        Color(.sRGB, red: color.red / 255, green: color.green / 255, blue: color.blue / 255)
    }

    static func image(_ pixels: StarPixels) -> UIImage {
        let data = Data(pixels.rgba) as CFData
        guard let provider = CGDataProvider(data: data), let image = CGImage(
            width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: pixels.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        ) else { return UIImage() }
        return UIImage(cgImage: image)
    }

    /// Paper grain over `rect`: specks light and dark, the same every run.
    static func grain(in context: GraphicsContext, rect: CGRect, opacity: CGFloat) {
        var ctx = context
        ctx.opacity *= opacity
        ctx.fill(Path(rect), with: .tiledImage(grainTile, origin: rect.origin))
    }

    private static let grainTile: Image = {
        var random = SeededRandom(9)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { renderer in
            for _ in 0..<1100 {
                let light = random.next() >= 0.5
                let alpha = random.next() * 0.45
                (light ? UIColor.white : UIColor.black).withAlphaComponent(alpha).setFill()
                renderer.fill(CGRect(x: random.next() * 96, y: random.next() * 96, width: 1, height: 1))
            }
        }
        return Image(uiImage: image)
    }()
}

/// The demo's mulberry32: the same specks and fibres as the demo.
struct SeededRandom {
    private var state: UInt32

    init(_ seed: UInt32) { state = seed }

    mutating func next() -> CGFloat {
        state = state &+ 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return CGFloat(t ^ (t >> 14)) / 4_294_967_296
    }
}
