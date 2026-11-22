import MiraNoteKit
import SwiftUI

// A port of design X's glass jar (debug/star-anim/X/proto.html, bodyPath,
// drawJarBack, drawJarFront): x/y are jar units, the jar's foot at the
// origin, 124 wide, its cap's top at y -170. The jar and its views are
// one file, as the prototype's jar is one drawing; where its stars lie
// is StarPile.swift.
// swiftlint:disable identifier_name

// MARK: - Jar drawing

/// Where the jar's parts sit in its frame: a short screw cap the width of
/// the rim, a rim, a short neck, rounded shoulders and a body with soft
/// bottom corners (design X).
struct JarGeometry {
    /// Width over height of the whole jar, cap included.
    static let aspect: CGFloat = 124 / 170

    let size: CGSize

    /// Points per jar unit.
    var unit: CGFloat { size.width / 124 }

    /// A jar-unit point in the frame.
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: (x + 62) * unit, y: (y + 170) * unit)
    }

    var mouthWidth: CGFloat { 80 * unit }
    /// The bottom of the neck: where dropping stars come in.
    var mouthY: CGFloat { point(0, -128).y }
    var shoulderY: CGFloat { point(0, -100).y }
    var corner: CGFloat { 12 * unit }
    static let stroke: CGFloat = 1.5

    /// The inside of the body, where stars may lie.
    var interior: JarInterior {
        let inset = Self.stroke + 2
        return JarInterior(
            rect: CGRect(x: inset, y: shoulderY, width: size.width - 2 * inset,
                         height: size.height - shoulderY - inset),
            corner: corner - inset
        )
    }

    /// The glass's outline `inset` points in from its outside, the neck
    /// included.
    func outline(inset: CGFloat, closed: Bool = true) -> Path {
        JarArt.body(inset: inset / unit, closed: closed)
            .applying(CGAffineTransform(scaleX: unit, y: unit).translatedBy(x: 62, y: 170))
    }
}

/// The glass jar, drawn in jar units on a context whose origin is the
/// jar's foot: the back glass (behind the stars), the front glass and
/// rim (over them), and the knurled screw cap.
enum JarArt {
    /// The glass's tints, from the theme (`Theme.jarGlass`). The cream
    /// glass is the prototype's; on Forest's dark green it reads milky, so
    /// Forest tints its own (#243). Highlights, twine and cap are the same
    /// in every theme.
    struct Glass: Equatable {
        /// The back glass, left to right (stops at 0, 0.35, 0.75 and 1).
        let body: [Color]
        let rimBack: Color
        let outline: Color
        let rimEdge: Color
        /// The front glass's faint tint, its right edge's shade, the band
        /// at its foot and the rim's face.
        let tint: Color
        let edge: Color
        let foot: Color
        let rim: Color

        static let cream = Glass(
            body: [rgba(206, 222, 216, 0.34), rgba(255, 255, 255, 0.14), rgba(205, 220, 215, 0.22),
                   rgba(160, 182, 176, 0.34)],
            rimBack: rgba(110, 120, 115, 0.35), outline: rgba(104, 116, 110, 0.55), rimEdge: rgba(104, 116, 110, 0.5),
            tint: rgba(226, 236, 232, 0.1), edge: rgba(110, 128, 122, 0.26), foot: rgba(255, 255, 255, 0.16),
            rim: rgba(255, 255, 255, 0.26))
    }

    /// The glass's outline, `i` jar units in.
    static func body(inset i: CGFloat = 0, closed: Bool = true) -> Path {
        var c = Path()
        c.move(to: CGPoint(x: -40 + i, y: -136))
        c.addLine(to: CGPoint(x: -40 + i, y: -128))
        c.addQuadCurve(to: CGPoint(x: -52 + i, y: -116), control: CGPoint(x: -40 + i, y: -120))
        c.addQuadCurve(to: CGPoint(x: -62 + i, y: -100), control: CGPoint(x: -62 + i, y: -112))
        c.addLine(to: CGPoint(x: -62 + i, y: -12))
        c.addQuadCurve(to: CGPoint(x: -50 + i, y: -i), control: CGPoint(x: -62 + i, y: -i))
        c.addLine(to: CGPoint(x: 50 - i, y: -i))
        c.addQuadCurve(to: CGPoint(x: 62 - i, y: -12), control: CGPoint(x: 62 - i, y: -i))
        c.addLine(to: CGPoint(x: 62 - i, y: -100))
        c.addQuadCurve(to: CGPoint(x: 52 - i, y: -116), control: CGPoint(x: 62 - i, y: -112))
        c.addQuadCurve(to: CGPoint(x: 40 - i, y: -128), control: CGPoint(x: 40 - i, y: -120))
        c.addLine(to: CGPoint(x: 40 - i, y: -136))
        if closed { c.closeSubpath() }
        return c
    }

    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    /// The jar's soft shadow on the ground, a warm caustic, the back glass
    /// and the back of the rim. `s` is points per jar unit.
    static func back(in context: GraphicsContext, s: CGFloat, glass: Glass, caustic: CGFloat = 0) {
        if s > 0.4 {
            let a = Ease.clamp((s - 0.4) / 0.6)
            var ground = context
            ground.translateBy(x: 0, y: 2)
            ground.scaleBy(x: 1, y: 0.13)
            let box = Path(CGRect(x: -90, y: -90, width: 180, height: 180))
            ground.fill(box, with: .radialGradient(Gradient(colors: [rgba(70, 52, 36, 0.26 * a), rgba(70, 52, 36, 0)]),
                                                   center: .zero, startRadius: 0, endRadius: 78))
            ground.fill(box, with: .radialGradient(
                Gradient(colors: [rgba(246, 186, 120, (0.18 + 0.35 * caustic) * a), rgba(246, 186, 120, 0)]),
                center: CGPoint(x: 16, y: -20), startRadius: 0, endRadius: 46))
        }
        context.fill(body(), with: .linearGradient(
            Gradient(stops: zip(glass.body, [0, 0.35, 0.75, 1]).map { Gradient.Stop(color: $0, location: $1) }),
            startPoint: CGPoint(x: -62, y: 0), endPoint: CGPoint(x: 62, y: 0)))
        var rim = Path()
        rim.addArc(center: .zero, radius: 1, startAngle: .radians(.pi), endAngle: .radians(2 * .pi), clockwise: false)
        context.stroke(rim.applying(CGAffineTransform(a: 40, b: 0, c: 0, d: 4.5, tx: 0, ty: -137)),
                       with: .color(glass.rimBack), lineWidth: max(0.8, 0.8 / s))
    }

    /// The glass over the stars: a faint tint, the highlights, a glint
    /// sweeping across (`glint` 0...1), a ripple of light (`rip`), the
    /// outline, the rim and the twine at the neck.
    static func front( // swiftlint:disable:this function_body_length
        in context: GraphicsContext, s: CGFloat, glass tints: Glass, glint: CGFloat = 0, rip: CGFloat = 0
    ) {
        let lw = max(1.1, 1 / s)
        var glass = context
        glass.clip(to: body())
        glass.fill(Path(CGRect(x: -70, y: -175, width: 140, height: 185)), with: .color(tints.tint))
        glass.fill(Path(CGRect(x: 44, y: -130, width: 18, height: 130)), with: .linearGradient(
            Gradient(colors: [tints.edge.opacity(0), tints.edge]),
            startPoint: CGPoint(x: 44, y: 0), endPoint: CGPoint(x: 62, y: 0)))
        glass.fill(Path(roundedRect: CGRect(x: -55, y: -104, width: 7, height: 84), cornerRadius: 3.5),
                   with: .linearGradient(Gradient(colors: [rgba(255, 255, 255, 0.85), rgba(255, 255, 255, 0.12)]),
                                         startPoint: CGPoint(x: -55, y: 0), endPoint: CGPoint(x: -48, y: 0)))
        glass.fill(Path(roundedRect: CGRect(x: -55, y: -15, width: 7, height: 4), cornerRadius: 2),
                   with: .color(rgba(255, 255, 255, 0.55)))
        glass.fill(Path(CGRect(x: 52, y: -96, width: 1.8, height: 58)), with: .color(rgba(255, 255, 255, 0.55)))
        var shoulder = Path()
        shoulder.move(to: CGPoint(x: -56, y: -106))
        shoulder.addQuadCurve(to: CGPoint(x: -42, y: -120), control: CGPoint(x: -52, y: -115))
        glass.stroke(shoulder, with: .color(rgba(255, 255, 255, 0.65)),
                     style: StrokeStyle(lineWidth: 2, lineCap: .round))
        if glint > 0, glint < 1 {
            let gx = -120 + 240 * glint, ga = 0.5 * sin(.pi * glint)
            glass.fill(Path(CGRect(x: -70, y: -150, width: 140, height: 152)), with: .linearGradient(
                Gradient(colors: [rgba(255, 255, 255, 0), rgba(255, 255, 255, ga), rgba(255, 255, 255, 0)]),
                startPoint: CGPoint(x: gx - 26, y: 10), endPoint: CGPoint(x: gx + 26, y: -40)))
        }
        if rip > 0, rip < 1 {
            glass.fill(Path(CGRect(x: -70, y: -150, width: 140, height: 152)),
                       with: .color(rgba(255, 244, 222, 0.5 * rip * (1 - rip))))
        }
        glass.fill(Path(CGRect(x: -62, y: -10, width: 124, height: 10)), with: .color(tints.foot))
        var foot = Path()
        foot.move(to: CGPoint(x: -58, y: -10))
        foot.addQuadCurve(to: CGPoint(x: 58, y: -10), control: CGPoint(x: 0, y: -7))
        glass.stroke(foot, with: .color(rgba(255, 255, 255, 0.55)), lineWidth: 0.9)

        context.stroke(body(), with: .color(tints.outline), lineWidth: lw)
        let rimRect = Path(roundedRect: CGRect(x: -44, y: -142, width: 88, height: 7), cornerRadius: 3.5)
        context.fill(rimRect, with: .color(tints.rim))
        context.stroke(rimRect, with: .color(tints.rimEdge), lineWidth: lw)
        var lip = Path()
        lip.move(to: CGPoint(x: -40, y: -141))
        lip.addLine(to: CGPoint(x: 40, y: -141))
        context.stroke(lip, with: .color(rgba(255, 255, 255, 0.75)), lineWidth: max(0.8, 0.8 / s))
        var near = Path()
        near.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(.pi), clockwise: false)
        context.stroke(near.applying(CGAffineTransform(a: 40, b: 0, c: 0, d: 4.5, tx: 0, ty: -137)),
                       with: .color(rgba(255, 255, 255, 0.6)), lineWidth: max(0.8, 0.8 / s))
        if s > 0.5 {
            // The twine and its bow at the neck.
            var twine = Path()
            twine.move(to: CGPoint(x: -40, y: -131))
            twine.addQuadCurve(to: CGPoint(x: 40, y: -131), control: CGPoint(x: 0, y: -128))
            twine.move(to: CGPoint(x: -40, y: -128.5))
            twine.addQuadCurve(to: CGPoint(x: 40, y: -128.5), control: CGPoint(x: 0, y: -125.5))
            twine.addPath(loop(-31, -128, -0.5))
            twine.addPath(loop(-20, -128, 0.5))
            twine.move(to: CGPoint(x: -25.5, y: -127))
            twine.addLine(to: CGPoint(x: -30, y: -116))
            twine.move(to: CGPoint(x: -25.5, y: -127))
            twine.addLine(to: CGPoint(x: -20, y: -117))
            context.stroke(twine, with: .color(Color(hex: 0xB0906A)),
                           style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
        if rip > 0, rip < 1 {
            let e = Ease.out3(rip)
            context.stroke(Path(ellipseIn: CGRect(x: -(44 + 22 * e), y: -140 - (5 + 5 * e),
                                                  width: 2 * (44 + 22 * e), height: 2 * (5 + 5 * e))),
                           with: .color(rgba(255, 255, 255, 0.7 * (1 - rip))), lineWidth: 1.5 / s)
        }
    }

    private static func loop(_ x: CGFloat, _ y: CGFloat, _ angle: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: -6, y: -3, width: 12, height: 6))
            .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: x, y: y)))
    }

    /// Where the cap is: seated, pushed aside askew on the rim (`ask` 1,
    /// the left half of the mouth open), or lifted off (`x`, `y`, `turn`).
    struct Cap {
        var ask: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rotation: CGFloat = 0
        /// The knurls' travel as it screws, jar units.
        var turn: CGFloat = 0
        var opacity: CGFloat = 1
    }

    /// One short knurled screw cap, exactly the rim's width (88 x 28).
    static func cap(in context: GraphicsContext, s: CGFloat, cap: Cap = Cap()) {
        guard cap.opacity > 0 else { return }
        var c = context
        c.opacity *= cap.opacity
        if cap.ask != 0 {
            c.translateBy(x: 44, y: -142)
            c.rotate(by: .radians(14 * .pi / 180 * cap.ask))
            c.translateBy(x: -44, y: 142)
            c.translateBy(x: 34 * cap.ask, y: 0)
        }
        c.translateBy(x: cap.x, y: -156 + cap.y)
        c.rotate(by: .radians(cap.rotation))
        let shape = Path(roundedRect: CGRect(x: -44, y: -14, width: 88, height: 28), cornerRadius: 7)
        c.fill(shape, with: .linearGradient(
            Gradient(stops: [.init(color: Color(hex: 0xE6CCA6), location: 0),
                             .init(color: Color(hex: 0xC9A275), location: 0.6),
                             .init(color: Color(hex: 0xAD8257), location: 1)]),
            startPoint: CGPoint(x: 0, y: -14), endPoint: CGPoint(x: 0, y: 14)))
        if s > 0.3 {
            var knurl = c
            knurl.clip(to: shape)
            var lines = Path()
            for kn in 0..<15 {
                let kx = -44 + (((CGFloat(kn) * 6 + cap.turn).truncatingRemainder(dividingBy: 88)) + 88)
                    .truncatingRemainder(dividingBy: 88)
                lines.move(to: CGPoint(x: kx, y: -7))
                lines.addLine(to: CGPoint(x: kx, y: 11))
            }
            knurl.stroke(lines, with: .color(rgba(110, 72, 38, 0.24)), lineWidth: 1.1)
            knurl.fill(Path(CGRect(x: -44, y: 10, width: 88, height: 4)), with: .color(rgba(90, 58, 30, 0.22)))
        }
        c.fill(Path(roundedRect: CGRect(x: -41, y: -12, width: 82, height: 4.5), cornerRadius: 2.25),
               with: .color(rgba(255, 244, 226, 0.6)))
        c.stroke(shape, with: .color(rgba(120, 84, 48, 0.4)), lineWidth: max(0.7, 0.7 / s))
    }
}

/// The jar's stars as jar units: a pile laid out as the jar screen lays
/// it out (`StarPile`), so every jar shows the same pile.
struct JarPile {
    struct Star {
        let id: Memory.ID
        let center: CGPoint
        let radius: CGFloat
        let rotation: CGFloat
        /// Its page's dress; plain paper until it is baked.
        let dress: StarDress
    }

    let stars: [Star]

    /// The jar screen's size of jar, to lay the pile out at.
    private static let reference = JarGeometry(size: CGSize(width: 124 * 2.3, height: 170 * 2.3))

    @MainActor
    init(_ ids: [Memory.ID]) {
        let geometry = Self.reference, unit = geometry.unit
        let pile = StarPile.layout(ids, in: geometry.interior)
        stars = zip(ids, pile.spots).map { id, spot in
            Star(id: id, center: CGPoint(x: spot.center.x / unit - 62, y: spot.center.y / unit - 170),
                 radius: pile.starSize * 0.45 / unit, rotation: CGFloat(spot.rotation * .pi / 180),
                 dress: StarFace.cached(id).map { .baked(Image(uiImage: $0)) } ?? .paint(.paper))
        }
    }

    /// The jar's frame in jar units, its foot at the origin.
    static let frame = CGRect(x: -62, y: -170, width: 124, height: 170)

    /// Draws the stars inside the glass, each in its page's dress; only
    /// those `include` takes.
    func draw(in context: GraphicsContext, except skipped: Memory.ID? = nil,
              where include: (Star) -> Bool = { _ in true }, offset: (Star) -> CGSize = { _ in .zero }) {
        var inside = context
        inside.clip(to: JarArt.body())
        for star in stars where star.id != skipped && include(star) {
            let shift = offset(star)
            PaperStar.draw(in: inside, at: CGPoint(x: star.center.x + shift.width, y: star.center.y + shift.height),
                           radius: star.radius, inner: PaperStar.rest, rotation: star.rotation, dress: star.dress,
                           style: .init(shadow: 0.35))
        }
    }

    /// The stars `include` takes, but `skipped`, drawn once into an image
    /// of the jar's `frame` (a point a jar unit): a drawing that shows the
    /// pile every frame draws this instead of each star.
    @MainActor
    func still(except skipped: Memory.ID?, where include: @escaping (Star) -> Bool) -> Image? {
        let renderer = ImageRenderer(content: Canvas { context, _ in
            var jar = context
            jar.translateBy(x: -Self.frame.minX, y: -Self.frame.minY)
            draw(in: jar, except: skipped, where: include)
        }.frame(width: Self.frame.width, height: Self.frame.height))
        renderer.scale = UITraitCollection.current.displayScale
        return renderer.cgImage.map { Image(decorative: $0, scale: renderer.scale) }
    }
}

/// The glass jar behind the jar screen's stars.
struct JarBackGlass: View {
    let geometry: JarGeometry
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { [glass = theme.jarGlass] context, _ in
            var ctx = context
            ctx.translateBy(x: 62 * geometry.unit, y: 170 * geometry.unit)
            ctx.scaleBy(x: geometry.unit, y: geometry.unit)
            JarArt.back(in: ctx, s: geometry.unit, glass: glass)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The front glass, rim and twine over the stars; the cap unless it is
/// off (a star is opening).
struct JarFrontGlass: View {
    let geometry: JarGeometry
    var capped = true
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { [glass = theme.jarGlass] context, _ in
            var ctx = context
            ctx.translateBy(x: 62 * geometry.unit, y: 170 * geometry.unit)
            ctx.scaleBy(x: geometry.unit, y: geometry.unit)
            JarArt.front(in: ctx, s: geometry.unit, glass: glass)
            if capped { JarArt.cap(in: ctx, s: geometry.unit) }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Home's header jar: the same glass jar, small, with this month's stars.
struct HeaderJar: View {
    let pile: JarPile
    /// Points per jar unit: about 19 x 26 pt in its 38 pt circle.
    static let unit: CGFloat = 0.15
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { [glass = theme.jarGlass] context, size in
            let s = Self.unit
            var ctx = context
            ctx.translateBy(x: size.width / 2, y: size.height / 2 + 78 * s)
            ctx.scaleBy(x: s, y: s)
            JarArt.back(in: ctx, s: s, glass: glass)
            #if DEBUG
            StarJarProbe.header(pile)
            #endif
            pile.draw(in: ctx)
            JarArt.front(in: ctx, s: s, glass: glass)
            JarArt.cap(in: ctx, s: s)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
// swiftlint:enable identifier_name
