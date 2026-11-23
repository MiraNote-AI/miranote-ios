import SwiftUI

/// The page as it folds (#206, design X): its bottom half swings back on
/// the middle crease, then the rows of its top half fold up accordion-
/// style onto the band, each a true perspective mountain fold
/// (`FoldCamera.projection`). Every piece is the page's own picture,
/// clipped to its rows; the flat part is one piece, so it shows no seams.
struct PagePose {
    var camera: FoldCamera
    /// The bottom half's turn: 0 flat, pi behind the top half.
    var half: CGFloat = 0
    /// The three pleats' turns in `FoldPlan` order; nil before them.
    var pleats: [CGFloat]?
    var shadow: CGFloat = 0
    var lift: CGFloat = 0
    var border: CGFloat = 0
    /// Crease lines where the page has been folded, 0...1.
    var creases: CGFloat = 0
    var halfCrease: CGFloat = 0
    /// How far down the flat page shows: past 560 the reading page's rest.
    var rows = StarPaper.height
    var corner = StarPaper.corner
    /// The page below 560, as the editor showed it: it fades as the fold
    /// starts (it rides on the bottom half).
    var tail: CGFloat = 0
}

struct FoldPageView: View {
    let paper: StarPaper
    let plan: FoldPlan
    let pose: PagePose

    private struct Piece: Identifiable {
        let id: Int
        let rows: ClosedRange<CGFloat>
        let fold: CATransform3D
        let shade: Color
        let shading: CGFloat
    }

    private static let dark = Color(.sRGB, red: 58 / 255, green: 24 / 255, blue: 34 / 255)
    private static let light = Color(.sRGB, red: 1, green: 248 / 255, blue: 238 / 255)
    /// Past this a turning piece is behind the band and not drawn.
    private static let hidden = 0.62 * CGFloat.pi

    var body: some View {
        let layout = self.layout
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                guard pose.shadow > 0 else { return }
                var ctx = context
                pose.camera.apply(to: &ctx)
                ctx.opacity *= pose.shadow
                let margin = StarPaper.shadowMargin, width = StarPaper.width, height = StarPaper.height
                ctx.draw(paper.shadow, in: CGRect(x: -width / 2 - margin,
                                                  y: layout.top - height / 2 - margin + 6 + 10 * pose.lift,
                                                  width: width + 2 * margin,
                                                  height: layout.bottom - layout.top + 2 * margin))
            }
            if pose.tail > 0 {
                // From a corner above 560: the bottom half's round corners
                // stay covered.
                pieceView(StarPaper.height - StarPaper.corner...paper.fullHeight, page: paper.fullHeight,
                          shade: .clear, shading: 0)
                    .opacity(pose.tail)
                    .projectionEffect(ProjectionTransform(pose.camera.projection(
                        abs(pose.half) > 1e-3 ? FoldPlan.hinge(StarPaper.half, pose.half, away: true)
                                              : CATransform3DIdentity)))
            }
            ForEach(layout.pieces) { piece in
                pieceView(piece.rows, shade: piece.shade, shading: piece.shading)
                    .projectionEffect(ProjectionTransform(pose.camera.projection(piece.fold)))
            }
            pieceView(layout.flat, shade: .clear, shading: 0)
                .projectionEffect(ProjectionTransform(pose.camera.projection(CATransform3DIdentity)))
            Canvas { context, _ in
                var ctx = context
                pose.camera.apply(to: &ctx)
                marks(in: ctx)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func pieceView(_ rows: ClosedRange<CGFloat>, page: CGFloat? = nil,
                           shade: Color, shading: CGFloat) -> some View {
        paper.page
            .resizable()
            .overlay(shade.opacity(shading))
            .frame(width: StarPaper.width, height: paper.fullHeight)
            .clipShape(Rows(rows: rows, page: page ?? pose.rows, corner: pose.corner))
    }

    /// A band of the page's rows, on a page `page` tall with round corners.
    private struct Rows: Shape {
        let rows: ClosedRange<CGFloat>
        let page: CGFloat
        let corner: CGFloat

        func path(in rect: CGRect) -> Path {
            Path(roundedRect: CGRect(x: 0, y: 0, width: rect.width, height: page), cornerRadius: corner)
                .intersection(Path(CGRect(x: -1, y: rows.lowerBound, width: rect.width + 2,
                                          height: rows.upperBound - rows.lowerBound)))
        }
    }

    // swiftlint:disable:next large_tuple
    private var layout: (pieces: [Piece], flat: ClosedRange<CGFloat>, top: CGFloat, bottom: CGFloat) {
        let tile = StarPaper.tile, half = StarPaper.half
        guard let angles = pose.pleats else {
            let folded = abs(pose.half) > 1e-3
            var pieces: [Piece] = []
            if folded, pose.half < Self.hidden {
                pieces.append(Piece(id: 9, rows: half...StarPaper.height,
                                    fold: FoldPlan.hinge(half, pose.half, away: true),
                                    shade: Self.dark, shading: 0.5 * max(0, sin(pose.half))))
            }
            let visible = folded ? half + (StarPaper.height - half) * max(0, cos(pose.half)) : StarPaper.height
            return (pieces, 0...(folded ? half : pose.rows), 0, visible)
        }
        let started = plan.folds.indices.filter { angles[$0] > 1e-3 }
        let aboveFolds = started.filter { plan.folds[$0].above }, belowFolds = started.filter { !plan.folds[$0].above }
        let r0 = aboveFolds.map { plan.folds[$0].crease }.max() ?? 0
        let r1 = belowFolds.map { plan.folds[$0].crease }.min() ?? half
        var pieces: [Piece] = []
        // A row folds behind its neighbour toward the band: below the
        // band, the outer rows go under.
        for row in Array(0..<paper.row) + Array(paper.row + 1..<4).reversed() {
            let turning = started.filter { plan.folds[$0].rows.contains(row) }
            guard !turning.isEmpty, turning.allSatisfy({ angles[$0] < Self.hidden }) else { continue }
            let own = plan.own(row).map { angles[$0] } ?? 0
            let above = row < paper.row
            pieces.append(Piece(id: row, rows: CGFloat(row) * tile...CGFloat(row + 1) * tile,
                                fold: plan.transform(of: row, angles: angles),
                                shade: above ? Self.light : Self.dark,
                                shading: (above ? 0.2 : 0.45) * max(0, sin(own))))
        }
        let innerAbove = aboveFolds.max { plan.folds[$0].crease < plan.folds[$1].crease }
        let innerBelow = belowFolds.min { plan.folds[$0].crease < plan.folds[$1].crease }
        let top = innerAbove.map { angles[$0] < .pi / 2 ? r0 - tile * cos(angles[$0]) : r0 } ?? 0
        let bottom = innerBelow.map { angles[$0] < .pi / 2 ? r1 + tile * cos(angles[$0]) : r1 } ?? half
        return (pieces, r0...r1, top, bottom)
    }

    private func marks(in context: GraphicsContext) {
        let creases = plan.folds.map(\.crease)
        guard let angles = pose.pleats else {
            let folded = abs(pose.half) > 1e-3
            if folded {
                var flat = context
                flat.clip(to: Path(CGRect(x: -StarPaper.width / 2, y: -StarPaper.height / 2,
                                          width: StarPaper.width, height: StarPaper.half)))
                PageMarks.halfShade(in: flat, angle: pose.half)
                if pose.half > .pi / 2 {
                    PageMarks.lip(in: context, at: StarPaper.half, down: true,
                                  opacity: Ease.seg(pose.half, .pi / 2, 0.75 * .pi))
                }
            }
            for crease in creases { PageMarks.crease(in: context, at: crease, opacity: pose.creases) }
            if !folded { PageMarks.crease(in: context, at: StarPaper.half, opacity: pose.halfCrease) }
            PageMarks.border(in: context, height: pose.rows, corner: pose.corner, opacity: pose.border)
            return
        }
        let started = plan.folds.indices.filter { angles[$0] > 1e-3 }
        let innerAbove = started.filter { plan.folds[$0].above }.max { plan.folds[$0].crease < plan.folds[$1].crease }
        let innerBelow = started.filter { !plan.folds[$0].above }.min { plan.folds[$0].crease < plan.folds[$1].crease }
        if let innerAbove {
            PageMarks.lip(in: context, at: plan.folds[innerAbove].crease, down: false,
                          opacity: Ease.seg(angles[innerAbove], .pi / 2, 0.75 * .pi))
        }
        if let innerBelow {
            PageMarks.lip(in: context, at: plan.folds[innerBelow].crease, down: true,
                          opacity: Ease.seg(angles[innerBelow], .pi / 2, 0.75 * .pi))
        } else {
            PageMarks.lip(in: context, at: StarPaper.half, down: true, opacity: 1)
        }
        for index in plan.folds.indices where !started.contains(index) {
            PageMarks.crease(in: context, at: creases[index], opacity: pose.creases)
        }
    }
}

// swiftlint:disable identifier_name

// MARK: - Page marks

/// What the page draws over its flat part: crease lines where it will
/// fold or has folded, the lip where paper turns behind it, its border.
enum PageMarks {
    static func crease(in context: GraphicsContext, at v: CGFloat, opacity a: CGFloat) {
        guard a > 0.003 else { return }
        let y = v - StarPaper.height / 2, x0 = -StarPaper.width / 2 + 1.5, w = StarPaper.width - 3
        let ink = Color(.sRGB, red: 70 / 255, green: 30 / 255, blue: 50 / 255)
        context.fill(Path(CGRect(x: x0, y: y - 2.5, width: w, height: 5)), with: .color(ink.opacity(0.06 * a)))
        context.fill(Path(CGRect(x: x0, y: y - 0.45, width: w, height: 0.9)), with: .color(ink.opacity(0.24 * a)))
        context.fill(Path(CGRect(x: x0, y: y + 0.7, width: w, height: 0.8)),
                     with: .color(Color(.sRGB, red: 1, green: 246 / 255, blue: 236 / 255, opacity: 0.45 * a)))
    }

    /// A fold edge where the paper turns behind: a thin lip of its back
    /// and a highlight. `down` when the paper beyond lies below.
    static func lip(in context: GraphicsContext, at v: CGFloat, down: Bool, opacity a: CGFloat) {
        guard a > 0.003 else { return }
        let y = v - StarPaper.height / 2, x0 = -StarPaper.width / 2 + 1, w = StarPaper.width - 2
        context.fill(Path(CGRect(x: x0, y: down ? y : y - 2.5, width: w, height: 2.5)),
                     with: .color(Color(.sRGB, red: 120 / 255, green: 58 / 255, blue: 72 / 255, opacity: 0.85 * a)))
        context.fill(Path(CGRect(x: x0, y: down ? y - 1 : y + 0.2, width: w, height: 0.8)),
                     with: .color(Color(.sRGB, red: 1, green: 240 / 255, blue: 230 / 255, opacity: 0.55 * a)))
    }

    /// The shade the folded half casts on the flat half above its crease.
    static func halfShade(in context: GraphicsContext, angle: CGFloat) {
        let s = abs(sin(angle)), y = StarPaper.half - StarPaper.height / 2
        let ink = Color(.sRGB, red: 60 / 255, green: 25 / 255, blue: 35 / 255)
        context.fill(Path(CGRect(x: -StarPaper.width / 2, y: y - 34, width: StarPaper.width, height: 34)),
                     with: .linearGradient(Gradient(colors: [ink.opacity(0), ink.opacity(0.16 * s)]),
                                           startPoint: CGPoint(x: 0, y: y - 34), endPoint: CGPoint(x: 0, y: y)))
    }

    static func border(in context: GraphicsContext, height: CGFloat, corner: CGFloat, opacity: CGFloat) {
        guard opacity > 0 else { return }
        let rect = CGRect(x: -StarPaper.width / 2 + 0.5, y: -StarPaper.height / 2 + 0.5,
                          width: StarPaper.width - 1, height: height - 1)
        context.stroke(Path(roundedRect: rect, cornerRadius: corner),
                       with: .color(Color(.sRGB, red: 1, green: 245 / 255, blue: 235 / 255, opacity: 0.55 * opacity)),
                       lineWidth: 1)
    }
}
// swiftlint:enable identifier_name
